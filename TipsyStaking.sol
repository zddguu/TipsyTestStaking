// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";


interface IGinMinter {
    function mintGin(
        address _mintTo,
        uint256 _amount
    ) external;

    function allocateGin(
        address _mintTo,
        uint256 _allocatedAmount
    ) external;
}

interface ITipsy is IERC20 {
    function reflexToReal(
        uint _amount
    ) external view returns (uint256);

    function realToReflex(
        uint _amount
    ) external view returns (uint256);
}

abstract contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
	//transfer to non 0 addy during constructor when deploying 4real to prevent our base contracts being taken over. Ensures only our proxy is usable
        //_transferOwnership(address(~uint160(0)));
        _transferOwnership(address(uint160(0)));
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable123: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() external virtual onlyOwner {
        _transferOwnership(address(0x000000000000000000000000000000000000dEaD));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) external virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function initOwnership(address newOwner) public virtual {
        require(_owner == address(0), "Ownable: owner already set");
        require(newOwner != address(0), "Ownable: new owner can't be 0 address");
        _owner = newOwner;
        emit OwnershipTransferred(address(0), newOwner);
    }

}
/**
 * @title Storage
 * @dev Store & retrieve value in a variable
 */
contract TipsyStaking is Ownable, Initializable, Pausable {

    //mapping(address => uint) private stakedBalances;
    mapping(address => UserAction) public userInfoMap;

    mapping(uint8 => UserLevel2) public UserLevels; 
    mapping(uint8 => string) LevelNames; 

    uint256 public totalWeight;

    uint8 private _levelCount;

    address private WETH;

    //address public lpTimelock;
    
    address public tipsy;
    address private gin;


    uint public lockDuration;

    uint public lastAction;


    uint _rTotal = 0;

    //uint public ginDripRate = 1e6; //Total amount of Gin to drip per second
    uint public ginDripPerUser; //Max amount per user to drip per second

    bool actualMint; //

    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

        struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of CAKEs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accCakePerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accCakePerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    struct UserAction{
        uint256 lastAction;
        uint256 lastWeight;
        uint256 rewardDebt;
        uint256 lastRewardBlock;
        uint256 rewardEarnedNotMinted;
        uint8 userLevel;
    }

        struct UserLevel{
        uint256 amountStaked;
        uint256 stakingLevel;
    }

    struct UserLevel2{
        uint256 minimumStaked;
        uint256 multiplier; //1e4
    }

        event GinAllocated(
        address indexed user,
        address indexed amount
    );

        event LiveGin(
        address indexed ginAddress,
        bool indexed live
    );

        event LockDurationChanged(
        uint indexed oldLock,
        uint indexed newLock
    );

        event Staked(
        address indexed from,
        uint indexed amount,
        uint indexed newTotal
    );

        event Unstaked(
        address indexed to,
        uint indexed amount,
        uint indexed newTotal
    );

        event LevelModified(
        address indexed to,
        uint indexed amount,
        uint indexed newTotal
    );

    function reflexToReal(uint _reflexAmount) public view returns (uint){
        //Mittens note, mockup. RealVersion should use ITipsy interface
        //ITipsy(tipsy).reflexToReal(_reflexAmount);
        return _reflexAmount * 1e18 / _rTotal;
    }  

    function realToReflex(uint _realAmount) public view returns (uint){
        //Mittens note, mockup. RealVersion should use ITipsy interface
        //ITipsy(tipsy).realToReflex(_reflexAmount);
        return _realAmount * _rTotal / 1e18;
    }  

    function ginReward(uint time, uint multiplier) public view returns(uint)
    {
        return (block.timestamp - time * ginDripPerUser * multiplier / 1e4);
    }

    function setGinAddress(address _gin) private onlyOwner
    {
        require (_gin != address(0));
        actualMint = true;
        gin = _gin;
        //emit(we live)
    }

    //New stake strategy is to convert reflex amount to real_amount and use real_amount as weight 
    function Stake(uint amount) public whenNotPaused returns (uint)
    {
        Harvest();
        uint realAmount = reflexToReal(amount);
        //IERC20(tipsy).transferFrom(msg.sender, address(this), amount);
        //Measure all weightings in real space
        userInfoMap[msg.sender].lastAction = block.timestamp;
        userInfoMap[msg.sender].lastWeight += realAmount;
        //userInfoMap[msg.sender].lastRewardBlock = block.timestamp;
        totalWeight += realAmount;
        emit Staked(msg.sender, amount, userInfoMap[msg.sender].lastWeight);
        return amount;
    }

    function setLockDuration(uint _newDuration) public onlyOwner
    {
        lockDuration = _newDuration;
    }

    function GetLockDurationOK() public view returns (bool)
    {
        return userInfoMap[msg.sender].lastAction + lockDuration <= block.timestamp;
        //require (userInfoMap[msg.sender].lastAction + lockDuration >= block.timestamp, "Can't unlock so soon!");
    }

    //New unstake strategy is to convert real_amount weight to reflex amount and use real_amount as weight 
    function Unstake(uint _amount) public whenNotPaused returns(uint _tokenToReturn)
    {   
        uint realAmount = reflexToReal(_amount);
        require(GetLockDurationOK(), "Can't unstake before lock is up!");
        require(_amount > 0, "Can't unstake 0");
        require (userInfoMap[msg.sender].lastWeight >= realAmount, "Can't unstake this much");
        Harvest();
        totalWeight -= realAmount;
        userInfoMap[msg.sender].lastWeight -= realAmount;
        userInfoMap[msg.sender].lastAction = block.timestamp;
        //_tokenToReturn = IERC20(tipsy).balanceOf(address(this)) * totalWeight / realAmount;
        //instead assume 100 tokens
        _tokenToReturn = totalWeight / _amount;
        //do a transfer to user
        //IERC20(tipsy).transfer(msg.sender, _tokenToReturn);
        emit Unstaked(msg.sender, _amount, userInfoMap[msg.sender].lastWeight);
        return _tokenToReturn;
    }

    function UnstakeAll() public whenNotPaused returns (uint _tokenToReturn)
    {
        //Do an unstake with all available tokens
        return 0;
    }

    function EmergencyUnstake(uint _amount) public returns (uint _tokenToReturn)
    //Maybe?
    {
        require(GetLockDurationOK(), "Can't unstake before lock is up!");
        require(_amount > 0, "Can't unstake 0");
        require (userInfoMap[msg.sender].lastWeight >= _amount, "Can't unstake this much");
        totalWeight -= _amount;
        userInfoMap[msg.sender].lastWeight -= _amount;
        userInfoMap[msg.sender].lastAction = block.timestamp;
        userInfoMap[msg.sender].lastRewardBlock = block.timestamp;
        //_tokenToReturn = IERC20(tipsy).balanceOf(address(this)) * totalWeight / _amount;
        //instead assume 100 tokens
        _tokenToReturn = totalWeight / _amount;
        //do a transfer to user
        return _tokenToReturn;
    }

    function getUserLevel(address _user) public view returns (uint _level)
    {
        _level = getLevel(userInfoMap[_user].lastWeight);
        return _level;
    }

    function getUserLevelTest() public view returns (string memory _level)
    {
        address user = msg.sender;
        _level = getLevelByStaked(userInfoMap[msg.sender].lastWeight);
        return _level;
    }

    function HarvestCalc(address _user) public view returns (uint _amount)
    {
        return (block.timestamp - userInfoMap[_user].lastRewardBlock) * ginDripPerUser * UserLevels[getLevel(GetBal(_user))].multiplier/1e3;
    }

    function Harvest() public whenNotPaused returns(uint hello1)
    {
        hello1 = HarvestCalc(msg.sender);
        if (hello1 == 0) return hello1;
        userInfoMap[msg.sender].lastRewardBlock = block.timestamp;
        if (!actualMint)
        {
            userInfoMap[msg.sender].rewardEarnedNotMinted += hello1;
        }
        else if (actualMint && userInfoMap[msg.sender].rewardEarnedNotMinted > 0)
        {
            userInfoMap[msg.sender].rewardEarnedNotMinted = 0;
            hello1 = hello1 + userInfoMap[msg.sender].rewardEarnedNotMinted;
            userInfoMap[msg.sender].rewardDebt += hello1;
            IGinMinter(gin).mintGin(msg.sender, hello1);
        }
        else
        {
            IGinMinter(gin).mintGin(msg.sender, hello1);
            userInfoMap[msg.sender].rewardDebt += hello1;
        }
        return hello1;
    }

    function GetBal(address user) public view returns (uint) {

        return userInfoMap[user].lastWeight;
    }

    function GetBalReflex(address user) public view returns (uint)
    {
        return realToReflex(userInfoMap[user].lastWeight);
    }

    constructor()
    {
        //Testing only. Real version should be initialized()
        initialize(msg.sender, address(1));
        addLevel(0, 5, 1000);
        addLevel(1, 10, 2000);
        addLevel(2, 100, 3000);
        setLevelName(0, "Tipsy Bronze");
        setLevelName(1, "Tipsy Silver");
        setLevelName(2, "Tipsy Gold");
        setLevelName(~uint8(0), "No Level");
        ginDripPerUser = 100;

    }

    function addLevel(uint8 _stakingLevel, uint amountStaked, uint multiplier) public onlyOwner
    {
        require(UserLevels[_stakingLevel].minimumStaked == 0, "Not a new level");
        setLevel(_stakingLevel, amountStaked, multiplier);
        _levelCount++;
    }

    function setLevel(uint8 stakingLevel, uint amountStaked, uint _multiplier) public onlyOwner
    {
        require(stakingLevel < ~uint8(0), "reserved for no stake status");
        if (stakingLevel == 0)
        {
            require(UserLevels[stakingLevel+1].minimumStaked == 0 || 
                    UserLevels[stakingLevel+1].minimumStaked > amountStaked, "tipsy: staking amount too low for 0");
        }
        else{
            require(UserLevels[stakingLevel-1].minimumStaked < amountStaked, "tipsy: staking amount too low for level");
        }
        UserLevels[stakingLevel].minimumStaked = amountStaked;
        UserLevels[stakingLevel].multiplier = _multiplier;
    }

    function setLevelName(uint8 stakingLevel, string memory _name) public onlyOwner
    {
        LevelNames[stakingLevel] = _name;
    }

    function deleteLevel(uint8 stakingLevel) public onlyOwner returns (bool)
    {
        require(stakingLevel == _levelCount-1, "must delete from last level");
        UserLevels[stakingLevel].minimumStaked = 0;
        UserLevels[stakingLevel].multiplier = 0;
        _levelCount--;
        return true;
    }

    function getLevel(uint amountStaked) public view returns (uint8)
    {
        //for loop not ideal here, but there will only be 3 levels, so not a big deal
        uint baseLine = UserLevels[0].minimumStaked;
        if (amountStaked < baseLine) return ~uint8(0);
        else {
            for (uint8 i = 1; i < _levelCount; i++)
            {
                if (UserLevels[i].minimumStaked > amountStaked) return i-1;
            }
        return _levelCount-1;
        }
    }

    function getLevelByStaked(uint amountStaked) public view returns (string memory)
    {
        uint8 _stakingLevel =  getLevel(amountStaked);
        return LevelNames[_stakingLevel];
    }

    function initialize(address owner_, address _tipsy) public initializer
    {   
        require(owner_ != address(0), "tipsy: owner can't be 0 address");
        require(_tipsy != address(0), "tipsy: Tipsy can't be 0 address");
        initOwnership(owner_);
        lockDuration = 90 days;
        actualMint = false;
    }

    //Reference only
    struct PoolInfo {
        address lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. CAKEs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that CAKEs distribution occurs.
        uint256 accCakePerShare; // Accumulated CAKEs per share, times 1e12. See below.
    }

}
