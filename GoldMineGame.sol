pragma solidity ^0.4.12;

import 'zeppelin-solidity/contracts/math/SafeMath.sol';

contract ContractAccessControl {
    

    /// @dev Emited when contract is upgraded - See README.md for updgrade plan
    event ContractUpgrade(address newContract);

    // The addresses of the accounts (or contracts) that can execute actions within each roles.
    address public ceoAddress;
    address public cfoAddress;
    address public cooAddress;

    // @dev Keeps track whether the contract is paused. When that is true, most actions are blocked
    bool public paused = false;

    /// @dev Access modifier for CEO-only functionality
    modifier onlyCEO() {
        require(msg.sender == ceoAddress);
        _;
    }

    /// @dev Access modifier for CFO-only functionality
    modifier onlyCFO() {
        require(msg.sender == cfoAddress);
        _;
    }

    /// @dev Access modifier for COO-only functionality
    modifier onlyCOO() {
        require(msg.sender == cooAddress);
        _;
    }

    modifier onlyCLevel() {
        require(
            msg.sender == cooAddress ||
            msg.sender == ceoAddress ||
            msg.sender == cfoAddress
        );
        _;
    }

    function _checkIsCLevel() view internal{
        require(
            msg.sender == cooAddress ||
            msg.sender == ceoAddress ||
            msg.sender == cfoAddress
        );
    }

    /// @dev Assigns a new address to act as the CEO. Only available to the current CEO.
    /// @param _newCEO The address of the new CEO
    function setCEO(address _newCEO) external onlyCEO {
        require(_newCEO != address(0));

        ceoAddress = _newCEO;
    }

    /// @dev Assigns a new address to act as the CFO. Only available to the current CEO.
    /// @param _newCFO The address of the new CFO
    function setCFO(address _newCFO) external onlyCEO {
        require(_newCFO != address(0));

        cfoAddress = _newCFO;
    }

    /// @dev Assigns a new address to act as the COO. Only available to the current CEO.
    /// @param _newCOO The address of the new COO
    function setCOO(address _newCOO) external onlyCEO {
        require(_newCOO != address(0));

        cooAddress = _newCOO;
    }

    /*** Pausable functionality adapted from OpenZeppelin ***/

    /// @dev Modifier to allow actions only when the contract IS NOT paused
    modifier whenNotPaused() {
        require(!paused);
        _;
    }

    /// @dev Modifier to allow actions only when the contract IS paused
    modifier whenPaused {
        require(paused);
        _;
    }

    /// @dev Called by any "C-level" role to pause the contract. Used only when
    ///  a bug or exploit is detected and we need to limit damage.
    function pause() external onlyCLevel whenNotPaused {
        paused = true;
    }

    /// @dev Unpauses the smart contract. Can only be called by the CEO, since
    ///  one reason we may pause the contract is when CFO or COO accounts are
    ///  compromised.
    /// @notice This is public rather than external so it can be called by
    ///  derived contracts.
    function unpause() public onlyCEO whenPaused {
        // can't unpause if contract was upgraded
        paused = false;
    }
}



contract GoldMineGame is ContractAccessControl{
    using SafeMath for uint256;

    enum GoldMineStatus { Prepare, Normal ,Selling, Closed }

    event SetGameConfig(uint256 cancelHireTime,uint256 buyHireMaxPercent);
    event CreateGoldMine(uint256 goldMineIndex,uint256 price,uint256 finneyValue,uint256 maxBitNum,uint256 bitPrice,address owner,GoldMineStatus status);
    event BuyGoldMine(uint256 goldMineIndex,address owner);
    event UserCreateGoldMineHire(uint256 goldMineIndex,address worker,uint256 bitNum);
    event RebuildGoldMineHire(uint256 goldMineIndex,uint256 rebuildTimes);
    event BuildWinnerOfGoleMine(uint256 goldMineIndex,address winner,uint256 goldValue);
    event PayGoldCoinToUser(address user,uint256 coinNum);
    event UserDrawGoldCoin(address user,uint256 coinNum);
    event UserCancelGoldMineHire(uint256 goldMineIndex,address user,uint256 backCoinNum,uint256 cancelBitNum);
    event ExpDrawGoldCoin(address user,uint256 coinNum);


    uint256 private config_cancelHireTime = 3600*48;
    uint256 private config_buyHireMaxPercent = 10;
    uint256 private config_goldCoinValue = 1 finney;
    uint256 private config_winnerRecordNum = 50 ;
    uint256 private config_userHireHidsNum = 10 ;

    struct GoldMine {
        uint256 price;
        uint256 finneyValue;
        uint256 maxBitNum;
        uint256 bitPrice;
        address owner;
        GoldMineStatus status;
    }

    struct GoldMineHireWorker{
        address owner;
        uint256 bitNum;
        uint256 payCoinNum;
        uint256 payLastTime;
    }

    struct GoldMineHire{
        uint256 hid;
        uint256 goldMineIndex;
        uint256 workerNum;
        uint256 curBitNum;
        mapping(uint256=>GoldMineHireWorker) workerMap;
        bool finished;
        address winner;
        uint256 rebuildTimes;
    }

    struct UserHireRecord{
        uint256 hid;
        uint256 goldMineIndex;
    }


    struct GoldMineWinnerRecord{
        uint256 hid;
        address winner;
        uint256 goldMineIndex;
        uint256 winGoldCoin;
        uint256 winTime;
    }


    uint256 internal expGoldCoin;
    uint256 internal gameGoldCoin;
    uint256 internal userGoldCoin;
    mapping(address => uint256) userGoldCoinMap;
    mapping(address => UserHireRecord[]) userHireRecordMap;
    mapping(uint256 => GoldMineWinnerRecord) winnerRecordMap;

    mapping(address => uint256[]) userHireHidsMap;

    GoldMine[] goldMines;
    GoldMineWinnerRecord[] winnerRecords;

    uint256 internal winTotalTimes;
    uint256 internal winTotalGoldCoins;

    uint256 internal goldMineHireHid = 10000;



    mapping(uint256=>GoldMineHire) goldMineHireMap;

//    constructor() public {
//        ceoAddress = msg.sender;
//        cfoAddress = msg.sender;
//        cooAddress = msg.sender;
//    }

    function GoldMineGame() public {
        ceoAddress = msg.sender;
        cfoAddress = msg.sender;
        cooAddress = msg.sender;
        goldMineHireHid = 10000;
    }

    function kill() public onlyCEO{
       selfdestruct(ceoAddress);
    }

    function createGoldMine(uint256 finneyValue,uint256 price,uint256 maxBitNum,uint256 bitPrice,GoldMineStatus status) public onlyCLevel  returns (bool) {
        require(finneyValue>0 && price>0);
        require(bitPrice*maxBitNum > finneyValue);
        address owner = address(0);
//        if(status == GoldMineStatus.Normal){
//            owner = cfoAddress;
//        }
        GoldMine memory _goldMine = GoldMine({
            price:price,
            finneyValue:finneyValue,
            maxBitNum:maxBitNum,
            bitPrice:bitPrice,
            owner:owner,
            status:status
        });
        goldMines.push(_goldMine);

        uint256 goldMineIndex = goldMines.length-1;

        goldMineHireHid++;
        goldMineHireMap[goldMineIndex] = GoldMineHire({
            hid:goldMineHireHid,
            goldMineIndex:goldMineIndex,
            workerNum:0,
            curBitNum:0,
            finished:false,
            winner:address(0),
            rebuildTimes:0
        }) ;
        winnerRecordMap[goldMineHireHid] = GoldMineWinnerRecord({
            hid:goldMineHireHid,
            winner:address(0),
            goldMineIndex:goldMineIndex,
            winGoldCoin : 0,
            winTime : 0
        });

        emit CreateGoldMine(goldMineIndex,price,finneyValue,maxBitNum,bitPrice,owner,status);
        return true;

    }

    function getGameInfo() public view onlyCLevel returns(uint256 t_goldMineCount,uint256 t_expGoldCoin,uint256 t_gameGoldCoin,uint256 t_userGoldCoin,uint256 t_winTotalTimes,uint256 t_winTotalGoldCoins){
        t_goldMineCount = goldMines.length;
        t_expGoldCoin = expGoldCoin;
        t_gameGoldCoin = gameGoldCoin;
        t_userGoldCoin = userGoldCoin;

        t_winTotalTimes = winTotalTimes;
        t_winTotalGoldCoins = winTotalGoldCoins;



    }


    function setGameConfig(uint256 cancelHireTime,uint256 buyHireMaxPercent) public onlyCLevel returns (bool success) {
        if(cancelHireTime > 0){
            config_cancelHireTime = cancelHireTime;
        }
        if(buyHireMaxPercent > 0){
            config_buyHireMaxPercent = buyHireMaxPercent;
        }

        success = true;

        emit SetGameConfig(cancelHireTime,buyHireMaxPercent);

    }

    function getGameConfig() public view returns (uint256 cancelHireTime,uint256 buyHireMaxPercent) {
        cancelHireTime = config_cancelHireTime;
        buyHireMaxPercent = config_buyHireMaxPercent;
    }

    function expDrawGoldCoin(address user,uint256 coinNum) public onlyCFO returns (bool success){
        require(coinNum > 0 && expGoldCoin >= coinNum);
        uint256 eValue = coinNum.mul(config_goldCoinValue);
        expGoldCoin = expGoldCoin.sub(coinNum);

        if(user == address(0)){
            user = cfoAddress;
        }

        user.transfer(eValue);

        success = true;

        emit ExpDrawGoldCoin(user,coinNum);
    }

    function changeGoldMineStatus(uint256 index,GoldMineStatus status) public onlyCLevel  returns (bool) {
        require(index < goldMines.length);

        GoldMine storage _goldMine = goldMines[index];
        require(_goldMine.status != status);
        require(_goldMine.status == GoldMineStatus.Prepare);
        _goldMine.status = status;

//        if(status == GoldMineStatus.Normal && _goldMine.owner == address(0)){
//            _goldMine.owner = cfoAddress;
//        }

        return true;

    }


    function getGoldMineOfIndex(uint256 index) public view returns(uint256 price, uint256 finneyValue,address owner,uint256 maxBitNum,uint256 bitPrice,GoldMineStatus status){
        require(index >= 0 && index < goldMines.length);
        GoldMine storage _goldMine = goldMines[index];
        price = _goldMine.price;
        finneyValue = _goldMine.finneyValue;
        owner = _goldMine.owner;
        maxBitNum = _goldMine.maxBitNum;
        bitPrice = _goldMine.bitPrice;
        status = _goldMine.status;
    }


    function getGoldMineDetailOfIndex(uint256 index) public view returns(uint256 price, uint256 finneyValue,address owner,uint256 maxBitNum,uint256 bitPrice,GoldMineStatus status,uint256 workerNum,uint256 curBitNum,bool finished,address winner,uint256 hid){
        require(index >= 0 && index < goldMines.length);
        GoldMine storage _goldMine = goldMines[index];
        price = _goldMine.price;
        finneyValue = _goldMine.finneyValue;
        owner = _goldMine.owner;
        maxBitNum = _goldMine.maxBitNum;
        bitPrice = _goldMine.bitPrice;
        status = _goldMine.status;

        GoldMineHire storage _tmpHire = _getGoldMineHireByGoldMineIndex(index);

        workerNum = _tmpHire.workerNum;
        curBitNum = _tmpHire.curBitNum;
        finished = _tmpHire.finished;
        winner = _tmpHire.winner;
        hid = _tmpHire.hid;

    }


    function getGoldMineHireWorkerListOfIndex(uint256 index,uint256 getNum,bool orderDes) public view returns(address[] workers,uint[] bitNums){
        require(index >= 0);
        require(index < goldMines.length);
        GoldMineHire storage _tmpHire = _getGoldMineHireByGoldMineIndex(index);

        uint256 workerNum = _tmpHire.workerNum;
        if(getNum > workerNum){
            getNum = workerNum;
        }


        workers = new address[](getNum);
        bitNums = new uint[](getNum);

        GoldMineHireWorker memory _worker;
        uint256 i = 0;

        uint256 g_index = 0;
        for(i=0;i<getNum;i+=1){
            if(orderDes){
                g_index = workerNum - 1 - i;
            }else{
                g_index = i;
            }
            _worker = _tmpHire.workerMap[g_index];
            // _tmpString = _worker.owner + "," + _worker.bitNum;
            // reData.push(_tmpString);
            workers[i] = _worker.owner;
            bitNums[i] = _worker.bitNum;
        }

    }


    function getGoldMinesCount() public view returns(uint){
        return goldMines.length;
    }


    function _addToExpGoldCoin(uint256 coinNum) private{
        expGoldCoin = expGoldCoin.add(coinNum);


    }

    function _addToGameGoldCoin(uint256 coinNum) private{
        gameGoldCoin = gameGoldCoin.add(coinNum);
    }

    function _payGameGoldCoinToUser(address user,uint256 coinNum) internal{

        gameGoldCoin = gameGoldCoin.sub(coinNum) ;
        userGoldCoin = userGoldCoin.add(coinNum);

        userGoldCoinMap[user] = userGoldCoinMap[user].add(coinNum);

        emit PayGoldCoinToUser(user, coinNum);

    }


    function _payGameGoldCoinToExp(uint256 coinNum) internal{

        gameGoldCoin = gameGoldCoin.sub(coinNum) ;
        expGoldCoin = expGoldCoin.add(coinNum);

    }

    function buyGoldMineByIndex(uint256 index) payable public whenNotPaused returns(bool){
        require(index < goldMines.length);
        GoldMine storage _goldMine = goldMines[index];
        require(_goldMine.status == GoldMineStatus.Selling);
        require(msg.value >= _goldMine.price.mul(config_goldCoinValue) );


        uint256 buyGoldCoin = _goldMine.price;
        uint256 backMoney = msg.value.sub(buyGoldCoin.mul(config_goldCoinValue)) ;

        _goldMine.owner = msg.sender;
        _goldMine.status = GoldMineStatus.Normal;

        require( backMoney <= msg.value);
        msg.sender.transfer(backMoney);

        _addToExpGoldCoin(buyGoldCoin);

        //call event
        emit BuyGoldMine( index , msg.sender );

        return true;
    }


    function _getGoldMineHireByGoldMineIndex(uint256 goldMineIndex) internal view returns (GoldMineHire storage gMineHire){
        gMineHire = goldMineHireMap[goldMineIndex];
    }

    function _getUserCanBuyBitNum(address user,uint256 goldMineIndex,uint256 maxBitNum) internal view returns (uint256){
        GoldMine storage _goldMine = goldMines[goldMineIndex];
        require(_goldMine.status == GoldMineStatus.Normal);

        GoldMineHire storage _tmpHire = _getGoldMineHireByGoldMineIndex(goldMineIndex);

        uint256 canBuyMaxBitNum = _goldMine.maxBitNum - _tmpHire.curBitNum;
        uint256 base_canBuyMaxBitNum = _goldMine.maxBitNum.mul(config_buyHireMaxPercent).div(100);
        if(base_canBuyMaxBitNum < 1){
            base_canBuyMaxBitNum = 1;
        }

        if(maxBitNum <= 0){
            maxBitNum = base_canBuyMaxBitNum;
        }else{
            if(maxBitNum > base_canBuyMaxBitNum){
                maxBitNum = base_canBuyMaxBitNum;
            }
        }



        bool t_success = false;
        uint256 index = 0;
        (t_success,index) = _getGoldHireShipIndexOfWorker(goldMineIndex,user) ;
        if(t_success){
            GoldMineHireWorker storage _worker =  _tmpHire.workerMap[index];
            if(maxBitNum <= _worker.bitNum){
                return 0;
            }

            maxBitNum = maxBitNum.sub(_worker.bitNum);
        }


        uint256 bitNum = maxBitNum;

        if(bitNum > canBuyMaxBitNum){
            bitNum = canBuyMaxBitNum;
        }


        return bitNum;
    }


    function _createGoldMineHireWithBitNum(uint256 goldMineIndex,address user, uint256 bitNum,uint256 buyGoldCoin)  internal returns(bool success){


        _addHireShip(goldMineIndex,user,bitNum,buyGoldCoin);

        _addToGameGoldCoin(buyGoldCoin);

        //call event
        emit UserCreateGoldMineHire(goldMineIndex,msg.sender,bitNum);

        success = true;

        _checkToBuildWinnerOfGoleMineIndex(goldMineIndex);


    }




    function createGoldMineHire(uint256 goldMineIndex,uint256 maxBitNum) payable public whenNotPaused returns(bool success ,uint256 buyBitNum){
        require(msg.value > 0);

        GoldMine storage _goldMine = goldMines[goldMineIndex];

        uint256 canBuyBitNum = _getUserCanBuyBitNum(msg.sender,goldMineIndex,maxBitNum);
        require(canBuyBitNum > 0);

        uint256 bitNum = msg.value.div((_goldMine.bitPrice.mul(config_goldCoinValue))) ;

        if(bitNum > canBuyBitNum){
            bitNum = canBuyBitNum;
        }

//        ( success ,buyBitNum )= _createGoldMineHireWithBitNum( goldMineIndex, bitNum,0,false);

        uint256 buyGoldCoin = _goldMine.bitPrice * bitNum;

        require( msg.value >= buyGoldCoin.mul(config_goldCoinValue));
        uint256 backValue = msg.value.sub(buyGoldCoin.mul(config_goldCoinValue)) ;

        if(backValue>0){
            require(backValue < msg.value);
            msg.sender.transfer(backValue);
        }


        success = _createGoldMineHireWithBitNum(goldMineIndex,msg.sender,bitNum,buyGoldCoin);
        buyBitNum = bitNum;
    }



    function createGoldMineHireWithGoldCoin(uint256 goldMineIndex,uint256 maxBitNum,uint256 payCoinNum)  public whenNotPaused returns(bool success ,uint256 buyBitNum){
        require(payCoinNum > 0);

        GoldMine storage _goldMine = goldMines[goldMineIndex];

        uint256 canBuyBitNum = _getUserCanBuyBitNum(msg.sender,goldMineIndex,maxBitNum);
        require(canBuyBitNum > 0);

        uint256 bitNum = payCoinNum.div(_goldMine.bitPrice);

        if(bitNum > canBuyBitNum){
            bitNum = canBuyBitNum;
        }

        uint256 buyGoldCoin = _goldMine.bitPrice.mul(bitNum);

        require( payCoinNum >= buyGoldCoin);

        require(_deductUserCoin(msg.sender,buyGoldCoin));

        success = _createGoldMineHireWithBitNum(goldMineIndex,msg.sender,bitNum,buyGoldCoin);
        buyBitNum = bitNum;

    }


    function cancelGoldMineHireOfIndex(uint256 goldMineIndex) public returns(bool) {
        address worker = msg.sender;
        GoldMineHire storage _tmpHire = _getGoldMineHireByGoldMineIndex(goldMineIndex);
        bool success;
        uint256 index;
        (success, index) = _getGoldHireShipIndexOfWorker(goldMineIndex,worker) ;

        if(success){
            GoldMineHireWorker storage _worker =  _tmpHire.workerMap[index];
            require(_worker.owner == worker);
            uint256 curTime = now;
            uint256 cancelHireTime = config_cancelHireTime;

            if( curTime < _worker.payLastTime.add(cancelHireTime)){
                return false;
            }


            uint256 cancelBitNum = _worker.payCoinNum;
            uint256 backBitNum = _worker.bitNum;
            _worker.bitNum = 0;
            _worker.payCoinNum = 0;


            //remove worker
            if(_tmpHire.workerNum >0 && index < _tmpHire.workerNum-1){
                for(uint256 i = index;i < _tmpHire.workerNum-1 ; i++){
                    _tmpHire.workerMap[i] = _tmpHire.workerMap[i+1];
                }

                delete _tmpHire.workerMap[ _tmpHire.workerNum-1];

            }else{
                delete _tmpHire.workerMap[index];
            }

            _tmpHire.workerNum -= 1;

            //pay back coin to user
            _payGameGoldCoinToUser(worker,cancelBitNum);
            _tmpHire.curBitNum = _tmpHire.curBitNum.sub(backBitNum);

            //event
            emit UserCancelGoldMineHire(goldMineIndex,worker,backBitNum,cancelBitNum);

            return true;
        }else{
            return false;
        }


    }


    function getGoldMineHireOfIndex(uint256 goldMineIndex) public view returns(uint256 workerNum,uint256 curBitNum){

        GoldMineHire storage _tmpHire = _getGoldMineHireByGoldMineIndex(goldMineIndex);

        workerNum = _tmpHire.workerNum;
        curBitNum = _tmpHire.curBitNum;

    }

    function getGoldHireShipOfWorker(uint256 goldMineIndex,address worker) public view returns(address owner,uint256 bitNum){
        require(worker != address(0));
        GoldMineHire storage _tmpHire = _getGoldMineHireByGoldMineIndex(goldMineIndex);

        bool success;
        uint256 index;
        (success, index) = _getGoldHireShipIndexOfWorker(goldMineIndex,worker) ;
        if(success){
            GoldMineHireWorker storage _worker =  _tmpHire.workerMap[index];
            owner = _worker.owner;
            bitNum = _worker.bitNum;
        }
    }


    function getMyGoldHireShip(uint256 goldMineIndex) public view returns(address owner,uint256 bitNum,uint256 payCoinNum,uint256 payLastTime){
        address worker = msg.sender;
        GoldMineHire storage _tmpHire = _getGoldMineHireByGoldMineIndex(goldMineIndex);

        bool success;
        uint256 index;
        (success, index) = _getGoldHireShipIndexOfWorker(goldMineIndex,worker) ;
        if(success){
            GoldMineHireWorker storage _worker =  _tmpHire.workerMap[index];
            owner = _worker.owner;
            bitNum = _worker.bitNum;
            payCoinNum = _worker.payCoinNum;
            payLastTime = _worker.payLastTime;
        }
    }


    function getMyGoldHireRecord(uint256 getNum) public view returns(uint256[] hidList,uint256[] goldMineIndexList,bool[] finishedList,bool[] isWinnerList,uint256[] winGoldCoinList){
        address worker = msg.sender;

        if(getNum == 0){
            getNum = 10;
        }
 
        uint256[] storage hids = userHireHidsMap[worker];
        uint256 len = hids.length;

        if(getNum > len){
            getNum = len;
        }
        if(getNum > 0){
            hidList = new uint256[](getNum);
            goldMineIndexList = new uint256[](getNum);
            finishedList = new bool[](getNum);
            isWinnerList = new bool[](getNum);
            winGoldCoinList = new uint256[](getNum);


            for(uint256 i = 0; i < getNum ; i++ ){
                hidList[i] = hids[len - 1 - i];

                GoldMineWinnerRecord storage winRecord = winnerRecordMap[hidList[i]];
                goldMineIndexList[i] = winRecord.goldMineIndex;
                finishedList[i] = (winRecord.winner == address(0))?false:true;
                isWinnerList[i]   = (winRecord.winner == worker)?true:false;
                winGoldCoinList[i] =  (winRecord.winner == worker)?winRecord.winGoldCoin:0;

            }


        }


        
    }

    function getGoldHireShipOfIndex(uint256 goldMineIndex,uint256 index) public view returns(address owner,uint256 bitNum,uint256 payCoinNum,uint256 payLastTime){

        GoldMineHire storage _tmpHire = _getGoldMineHireByGoldMineIndex(goldMineIndex);
        require(index < _tmpHire.workerNum);
        GoldMineHireWorker storage _worker =  _tmpHire.workerMap[index];
        owner = _worker.owner;
        bitNum = _worker.bitNum;
        payCoinNum = _worker.payCoinNum;
        payLastTime = _worker.payLastTime;

    }

    function _getGoldHireShipIndexOfWorker(uint256 goldMineIndex,address worker) internal view returns(bool success ,uint256 index){
        require(worker != address(0));

        // GoldMineHire storage _tmpHire = goldMineHireMap[goldMineIndex];
        GoldMineHire storage _tmpHire = _getGoldMineHireByGoldMineIndex(goldMineIndex);
        for(uint256 i = 0; i< _tmpHire.workerNum ; i+=1){
            GoldMineHireWorker storage _worker = _tmpHire.workerMap[i];
            if(_worker.owner == worker){
                success = true;
                index = i;
                return;
            }
        }

        success = false;
        return ;
    }

    function _addHireShip(uint256 goldMineIndex, address worker,uint256 bitNum,uint256 payCoinNum) internal{
        require(bitNum > 0);
        // GoldMineHire storage _tmpHire = goldMineHireMap[goldMineIndex];
        GoldMineHire storage _tmpHire = _getGoldMineHireByGoldMineIndex(goldMineIndex);

        bool success;
        uint256 index;
        (success,index) = _getGoldHireShipIndexOfWorker(goldMineIndex,worker) ;
        if(success){
            _tmpHire.workerMap[index].bitNum = _tmpHire.workerMap[index].bitNum.add(bitNum) ;
            _tmpHire.workerMap[index].payLastTime = now;
            _tmpHire.workerMap[index].payCoinNum = _tmpHire.workerMap[index].payCoinNum.add(payCoinNum);

        }else{

            GoldMineHireWorker memory newWorker = GoldMineHireWorker({
                owner:worker,
                bitNum:bitNum,
                payCoinNum:payCoinNum,
                payLastTime:now
            });

            _tmpHire.workerNum += 1;
            uint256 workerIndex = _tmpHire.workerNum - 1;
            _tmpHire.workerMap[workerIndex] = newWorker;


            userHireHidsMap[worker].push(_tmpHire.hid);

            uint256 h_len = userHireHidsMap[worker].length;
            if(h_len > config_userHireHidsNum){
                delete userHireHidsMap[worker][h_len - config_userHireHidsNum - 1];
            }

            
        }

        _tmpHire.curBitNum = _tmpHire.curBitNum.add(bitNum) ;
    }


    function _makeRandomNum(uint256 minNum, uint256 maxNum,uint256 kkNum) internal view returns (uint256){
        require(maxNum > minNum);

        uint256 random = uint256 (keccak256(block.difficulty,now,kkNum));
        return minNum + ( random % (maxNum - minNum + 1) );
    }


    function _getRandomIndexByArray(uint256[] numArr ) internal view returns (uint256){

        uint256 totalNum = 0;
        uint256 i=0;
        for(i=0; i < numArr.length ; i++){
            totalNum += numArr[i];
        }

        uint256 r_num = _makeRandomNum(1,totalNum,uint256 (msg.sender) % 10000 );

        uint256 c_num = 0;
        uint256 p_index = numArr.length - 1;
        for(i=0; i < numArr.length ; i++){
            c_num += numArr[i];
            if(c_num >= r_num){
                p_index = i;
                break;
            }
        }

        return p_index;
    }

    function rebuildGoldMineHireOfGoleMineIndex(uint256 goldMineIndex) public whenNotPaused returns(bool){
        GoldMine storage goldMine = goldMines[goldMineIndex];

        if(goldMine.owner != address(0)){
            require(goldMine.owner == msg.sender);
        }else{
            _checkIsCLevel();
        }



        GoldMineHire storage goldMineHire = _getGoldMineHireByGoldMineIndex(goldMineIndex);
        require(goldMineHire.finished);


        uint256 rebuildTimes = goldMineHire.rebuildTimes + 1;

        goldMineHireHid++;
        goldMineHireMap[goldMineIndex] = GoldMineHire({
            hid:goldMineHireHid,
            goldMineIndex:goldMineIndex,
            workerNum:0,
            curBitNum:0,
            finished:false,
            winner:address(0),
            rebuildTimes:rebuildTimes
        }) ;


        winnerRecordMap[goldMineHireHid] = GoldMineWinnerRecord({
            hid:goldMineHireHid,
            winner:address(0),
            goldMineIndex:goldMineIndex,
            winGoldCoin : 0,
            winTime : 0
            });

        // event
        emit RebuildGoldMineHire(goldMineIndex,rebuildTimes);

        return true;

    }


    function _checkToBuildWinnerOfGoleMineIndex(uint256 goldMineIndex) internal returns(bool success,uint256 randomIndex,address winner,uint256 winnerGoldCoin,uint256 ownerGoldCoin){
        GoldMine storage goldMine = goldMines[goldMineIndex];
        GoldMineHire storage goldMineHire = _getGoldMineHireByGoldMineIndex(goldMineIndex);

        if( goldMineHire.curBitNum < goldMine.maxBitNum){
            success = false;
            return ;
        }

        if(goldMineHire.finished ){
            success = false;
            return ;
        }


        uint256[] memory numArr=new uint256[](goldMineHire.workerNum);
        for(uint256 i = 0;i<goldMineHire.workerNum;i += 1){
            numArr[i] = goldMineHire.workerMap[i].bitNum;
        }
        randomIndex = _getRandomIndexByArray(numArr);
        GoldMineHireWorker storage _worker = goldMineHire.workerMap[randomIndex];


        winner = _worker.owner;
        address owner = goldMine.owner;

        uint256 totalGoldCoin = goldMine.bitPrice.mul( goldMineHire.curBitNum );
        winnerGoldCoin = goldMine.finneyValue;
        ownerGoldCoin = totalGoldCoin.sub(winnerGoldCoin);


        success = true;

        goldMineHire.finished = true;
        goldMineHire.winner = winner;

        if(winnerGoldCoin > 0){
            _payGameGoldCoinToUser(winner,winnerGoldCoin);
        }
        if(ownerGoldCoin > 0){
            if(owner!=address(0)){
                _payGameGoldCoinToUser(owner,ownerGoldCoin);
            }else{
                _payGameGoldCoinToExp(ownerGoldCoin);
            }

        }

        //event
        emit BuildWinnerOfGoleMine(goldMineIndex,winner,winnerGoldCoin);


        // add win record
        GoldMineWinnerRecord memory winRecord = GoldMineWinnerRecord({
            hid:goldMineHire.hid,
            winner:winner,
            goldMineIndex:goldMineIndex,
            winGoldCoin:winnerGoldCoin,
            winTime:now
            });

        _addWinnerRecord(winRecord);


    }

    function buildWinnerOfGoleMineIndex(uint256 goldMineIndex) public whenNotPaused returns(bool success,uint256 randomIndex,address winner,uint256 winnerFinneyValue,uint256 ownerFinneyValue){

        GoldMine storage goldMine = goldMines[goldMineIndex];
        GoldMineHire storage goldMineHire = _getGoldMineHireByGoldMineIndex(goldMineIndex);
        require(goldMineHire.curBitNum >= goldMine.maxBitNum);
        require(goldMineHire.finished != true);

        (success,randomIndex,winner,winnerFinneyValue,ownerFinneyValue) = _checkToBuildWinnerOfGoleMineIndex(goldMineIndex);


    }

    function getUserCoinNum() public view returns (uint256 coinNum){
        address user = msg.sender;
        coinNum = userGoldCoinMap[user];
    }

    function _deductUserCoin(address user,uint256 coinNum) internal returns(bool) {
        if(coinNum > userGoldCoinMap[user]){
            return false;
        }
        userGoldCoinMap[user] = userGoldCoinMap[user].sub(coinNum);
        userGoldCoin = userGoldCoin.sub(coinNum);
        return true;
    }


    function userDrawGoldCoin(uint256 coinNum) public whenNotPaused returns (bool success){
        address user = msg.sender;
        uint256 userCoinNum = userGoldCoinMap[user];
        require(coinNum <= userCoinNum);


        require(_deductUserCoin(user,coinNum));

        uint256 eValue = coinNum.mul(config_goldCoinValue);

        user.transfer( eValue );

        success = true;

        emit UserDrawGoldCoin(user,coinNum);
    }


    function _addWinnerRecord(GoldMineWinnerRecord record) internal returns (bool){

        if(winTotalTimes + 1 > winTotalTimes){
            winTotalTimes = winTotalTimes + 1;
        }

        if(winTotalGoldCoins + record.winGoldCoin > winTotalGoldCoins){
            winTotalGoldCoins = winTotalGoldCoins + record.winGoldCoin;
        }

        winnerRecords.push(record);
        uint256 len = winnerRecords.length;
        if(len > config_winnerRecordNum){
            uint256 mIndex = len - config_winnerRecordNum - 1;
            delete winnerRecords[mIndex];
        }


        winnerRecordMap[record.hid] = record;

    }

    function getWinnerRecordList(uint256 getNum) public view returns (uint256[] hids,address[] winnerList,uint256[] goldMineIndexList,uint256[] winGoldCoinList,uint256[] winTimeList){

        uint256 len = winnerRecords.length;

        if(getNum > len){
            getNum = len;
        }
        if(len > config_winnerRecordNum){
            getNum = config_winnerRecordNum;
        }


        hids = new uint256[](getNum);
        winnerList = new address[](getNum);
        goldMineIndexList = new uint256[](getNum);
        winGoldCoinList = new uint256[](getNum);
        winTimeList = new uint256[](getNum);


        uint256 r_index = 0;
        for(uint256 i = 0; i < getNum; i++){
            r_index = len - 1 - i;
            GoldMineWinnerRecord storage record = winnerRecords[r_index];

            hids[i] = record.hid;
            winnerList[i] = record.winner;
            goldMineIndexList[i] = record.goldMineIndex;
            winGoldCoinList[i] = record.winGoldCoin;
            winTimeList[i] = record.winTime;
        }

    }
    
}


