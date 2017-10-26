pragma solidity 0.4.15;

import "zeppelin-solidity/contracts/lifecycle/Destructible.sol";
import "zeppelin-solidity/contracts/ownership/Contactable.sol";
import "./MonethaGateway.sol";
import "./MerchantDealsHistory.sol";
import './MerchantWallet.sol';


contract PaymentAcceptor is Destructible, Contactable {

    string constant VERSION = "1.0";
    
    MonethaGateway public monethaGateway;
    MerchantDealsHistory public merchantHistory;
    string public merchantId;
    uint public orderId;
    uint public price;
    address public client;
    State public state;

    enum State {Inactive, MerchantAssigned, OrderAssigned, Paid}

    modifier atState(State _state) {
        require(_state == state);
        _;
    }

    modifier transition(State _state) {
        _;
        state = _state;
    }

    function PaymentAcceptor(string _merchantId, MerchantDealsHistory _merchantHistory, MonethaGateway _monethaGateway) {
        changeMonethaGateway(_monethaGateway);
        setMerchantId(_merchantId, _merchantHistory);
    }

    function setMerchantId(string _merchantId, MerchantDealsHistory _merchantHistory) public
        atState(State.Inactive) transition(State.MerchantAssigned) onlyOwner 
    {
        require(bytes(_merchantId).length > 0);
        merchantId = _merchantId;
        merchantHistory = _merchantHistory;
    }

    function unassignMerchant() external
        atState(State.MerchantAssigned) transition(State.Inactive) onlyOwner
    {
        merchantId = "";
        merchantHistory = MerchantDealsHistory(0x0);
    }

    function assignOrder(uint _orderId, uint _price) external
        atState(State.MerchantAssigned) transition(State.OrderAssigned) onlyOwner 
    {
        require(_orderId != 0);
        require(_price != 0);

        orderId = _orderId;
        price = _price;
    }

    function () external payable
        atState(State.OrderAssigned) transition(State.Paid) 
    {
        require(msg.value == price);
        require(this.balance - msg.value == 0); //the order should not be paid already

        client = msg.sender;
    }

    function refundPayment(
        MerchantWallet _merchantWallet,
        uint32 _clientReputation,
        uint32 _merchantReputation,
        uint _dealHash
    )   external
        atState(State.Paid) transition(State.MerchantAssigned) onlyOwner
    {
        client.transfer(this.balance);
        
        updateReputation(
            _merchantWallet,
            _clientReputation,
            _merchantReputation,
            false,
            _dealHash
        );

        orderId = 0;
        price = 0;
    }

    function cancelOrder(
        MerchantWallet _merchantWallet,
        uint32 _clientReputation,
        uint32 _merchantReputation,
        uint _dealHash
    ) 
        external 
        atState(State.OrderAssigned) transition(State.MerchantAssigned) onlyOwner
    {
        //when client doesn't pay order is cancelled
        //future: update Client reputation

        updateReputation(
            _merchantWallet,
            _clientReputation,
            _merchantReputation,
            false,
            _dealHash
        );

        orderId = 0;
        price = 0;
    }

    function processPayment(
        MerchantWallet _merchantWallet, //merchantWallet is passing as a parameter 
                                        //for possibility to dynamically change it, 
                                        //if merchant requests for change
        uint32 _clientReputation,
        uint32 _merchantReputation,
        uint _dealHash
    ) 
        external
        atState(State.Paid) transition(State.MerchantAssigned) onlyOwner 
    {
        monethaGateway.acceptPayment.value(this.balance)(_merchantWallet);
        
        updateReputation(
            _merchantWallet,
            _clientReputation,
            _merchantReputation,
            true,
            _dealHash
        );

        orderId = 0;
        price = 0;
    }

    function changeMonethaGateway(MonethaGateway _newGateway) public onlyOwner {
        require(address(_newGateway) != 0x0);
        monethaGateway = _newGateway;
    }

    function updateReputation(
        MerchantWallet _merchantWallet,
        uint32 _clientReputation,
        uint32 _merchantReputation,
        bool _isSuccess,
        uint _dealHash
    ) internal 
    {
        merchantHistory.recordDeal(
            orderId,
            client,
            _clientReputation,
            _merchantReputation,
            _isSuccess,
            _dealHash
        );

        _merchantWallet.setCompositeReputation("total", _merchantReputation);
    }
}