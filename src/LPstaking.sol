

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

interface token is IERC20 {
    function mint(address recipient, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external ;
}

contract LPstaking is Ownable,ReentrancyGuard {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {

        uint256 vote;  
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt;
        uint256 xGNDrewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of GNDs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accGNDPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accGNDPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. GNDs to distribute per block.
        uint256 lastRewardTime;  // Last block time that GNDs distribution occurs.
        uint256 accGNDPerShare; // Accumulated GNDs per share, times 1e12. See below.
        uint256 accxGNDPerShare; // Accumulated GNDs per share, times 1e12. See below.
    }

    token public GND = token(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    token public xGND = token(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    // Dev address.
    address public devaddr;
    address public stakepool;
    // GND tokens created per block.
    uint256 public GNDPerSecond;
    uint256 public xGNDPerSecond;

    uint256 public totalGNDdistributed = 0;
    uint256 public xGNDdistributed = 0;

    // set a max GND per second, which can never be higher than 1 per second
    uint256 public constant maxGNDPerSecond = 1e18;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block time when GND mining starts.
    uint256 public immutable startTime;

    bool public withdrawable = false;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        uint256 _GNDPerSecond,
        uint256 _xGNDPerSecond,
        uint256 _startTime
    ) {

        GNDPerSecond = _GNDPerSecond;
        xGNDPerSecond = _xGNDPerSecond;
        startTime = _startTime;
    }

    function openWithdraw() external onlyOwner{
        withdrawable = true;
    }

    function supplyRewards(uint256 _amount) external onlyOwner {
        totalGNDdistributed = totalGNDdistributed.add(_amount);
        GND.transferFrom(msg.sender, address(this), _amount);
    }
    
    function closeWithdraw() external onlyOwner{
        withdrawable = false;
    }

            // Update the given pool's GND allocation point. Can only be called by the owner.
    function increaseAllocation(uint256 _pid, uint256 _allocPoint) internal {

        massUpdatePools();

        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo[_pid].allocPoint = poolInfo[_pid].allocPoint.add(_allocPoint);
    }
    
    function decreaseAllocation(uint256 _pid, uint256 _allocPoint) internal {

        massUpdatePools();

        totalAllocPoint = totalAllocPoint.sub(_allocPoint);
        poolInfo[_pid].allocPoint = poolInfo[_pid].allocPoint.sub(_allocPoint);
    }

    function vote(address _user, uint256 _amount, uint256 _pid) external {
        require(msg.sender == stakepool, "not stakepool");
        
        UserInfo storage user = userInfo[_pid][_user];
    
        if (_amount > user.vote){
            uint256 increaseAmount = _amount.sub(user.vote);
            user.vote = _amount;
            increaseAllocation(_pid, increaseAmount);
        } 
        else {
            uint256 decreaseAmount = user.vote.sub(_amount);
            user.vote = _amount;
            decreaseAllocation(_pid, decreaseAmount);
        }
        
 
    }

    function redeemVote(address _user, uint256 _pid) external {
        require(msg.sender == stakepool, "not stakepool");
        UserInfo storage user = userInfo[_pid][_user];
        decreaseAllocation(_pid, user.vote);
        user.vote = 0;
        
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Changes GND token reward per second, with a cap of maxGND per second
    // Good practice to update pools without messing up the contract
    function setGNDPerSecond(uint256 _GNDPerSecond) external onlyOwner {
        require(_GNDPerSecond <= maxGNDPerSecond, "setGNDPerSecond: too many GNDs!");

        // This MUST be done or pool rewards will be calculated with new GND per second
        // This could unfairly punish small pools that dont have frequent deposits/withdraws/harvests
        massUpdatePools(); 

        GNDPerSecond = _GNDPerSecond;
    }

    function setxGNDPerSecond(uint256 _xGNDPerSecond) external onlyOwner {
        require(_xGNDPerSecond <= maxGNDPerSecond, "setGNDPerSecond: too many GNDs!");

        // This MUST be done or pool rewards will be calculated with new GND per second
        // This could unfairly punish small pools that dont have frequent deposits/withdraws/harvests
        massUpdatePools(); 

        xGNDPerSecond = _xGNDPerSecond;
    }


    function checkForDuplicate(IERC20 _lpToken) internal view {
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; _pid++) {
            require(poolInfo[_pid].lpToken != _lpToken, "add: pool already exists!!!!");
        }

    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken) external onlyOwner {

        checkForDuplicate(_lpToken); // ensure you cant add duplicate pools

        massUpdatePools();

        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTime: lastRewardTime,
            accGNDPerShare: 0,
            accxGNDPerShare: 0
        }));
    }

    // Update the given pool's GND allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) external onlyOwner {

        massUpdatePools();

        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }



    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        _from = _from > startTime ? _from : startTime;
        if (_to < startTime) {
            return 0;
        }
        return _to - _from;
    }

    // View function to see pending GNDs on frontend.
    function pendingGND(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accGNDPerShare = pool.accGNDPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 GNDReward = multiplier.mul(GNDPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accGNDPerShare = accGNDPerShare.add(GNDReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accGNDPerShare).div(1e12).sub(user.rewardDebt);
    }

    function pendingxGND(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accxGNDPerShare = pool.accxGNDPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 xGNDReward = multiplier.mul(xGNDPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accxGNDPerShare = accxGNDPerShare.add(xGNDReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accxGNDPerShare).div(1e12).sub(user.xGNDrewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 GNDReward = multiplier.mul(GNDPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
        uint256 xGNDReward = multiplier.mul(xGNDPerSecond).mul(pool.allocPoint).div(totalAllocPoint);

        pool.accGNDPerShare = pool.accGNDPerShare.add(GNDReward.mul(1e12).div(lpSupply));
        pool.accxGNDPerShare = pool.accxGNDPerShare.add(xGNDReward.mul(1e12).div(lpSupply));
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens to MasterChef for GND allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accGNDPerShare).div(1e12).sub(user.rewardDebt);
        uint256 EsPending = user.amount.mul(pool.accxGNDPerShare).div(1e12).sub(user.xGNDrewardDebt);

        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accGNDPerShare).div(1e12);
        user.xGNDrewardDebt = user.amount.mul(pool.accxGNDPerShare).div(1e12);

        if(pending > 0 || EsPending >0) {
            GND.mint(msg.sender, pending);
            xGND.mint(msg.sender, EsPending);
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {  
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "withdraw: not good");
        require(withdrawable, "withdraw not opened");

        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accGNDPerShare).div(1e12).sub(user.rewardDebt);
        uint256 EsPending = user.amount.mul(pool.accGNDPerShare).div(1e12).sub(user.xGNDrewardDebt);

        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accGNDPerShare).div(1e12);
        user.xGNDrewardDebt = user.amount.mul(pool.accxGNDPerShare).div(1e12);

        if(pending > 0 || EsPending > 0) {
            GND.mint(msg.sender, pending);
            xGND.mint(msg.sender, EsPending);
        }
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function updateStakePool(address _pool) external onlyOwner {
        stakepool = _pool;
    } 
}