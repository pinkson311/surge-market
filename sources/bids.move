module surge::bids;

use sui::kiosk;
use std::ascii;
use sui::coin;
use sui::sui;
use sui::transfer_policy;
use sui::dynamic_object_field as dof;
use std::type_name;
use sui::event;

public struct Store has key {
    id: UID,
    escrow_kiosk_cap: kiosk::KioskOwnerCap,
}

public struct Escrow has store, key {
    id: UID,
    buyer: address,
}

public struct EscrowWithPurchaseCap<phantom T: store + key> has store, key {
    id: UID,
    buyer: address,
    purchase_cap: kiosk::PurchaseCap<T>,
}

public struct BidKey has copy, drop, store {
    bid_id: ID,
}

#[allow(lint(coin_field))]
public struct Bid has store, key {
    id: UID,
    nft_type: ascii::String,
    nft_id: Option<ID>,
    buyer: address,
    price: u64,
    wallet: coin::Coin<sui::SUI>,
    commission: u64,
    beneficiary: address,
}

public struct CreateBidEvent has copy, drop {
    bid_id: ID,
    nft_type: ascii::String,
    nft_id: ID,
    buyer: address,
    price: u64,
    commission: u64,
    beneficiary: address,
}

public struct CreateCollectionBidEvent has copy, drop {
    bid_id: ID,
    nft_type: ascii::String,
    token_amount: u64,
    buyer: address,
    price: u64,
    commission: u64,
    beneficiary: address,
}

public struct CancelBidEvent has copy, drop {
    bid_id: ID,
    nft_type: ascii::String,
    nft_id: ID,
    buyer: address,
    price: u64,
    commission: u64,
    beneficiary: address,
}

public struct CancelCollectionBidEvent has copy, drop {
    bid_id: ID,
    nft_type: ascii::String,
    buyer: address,
    price: u64,
    commission: u64,
    beneficiary: address,
}

public struct MatchBidEvent has copy, drop {
    bid_id: ID,
    nft_type: ascii::String,
    nft_id: ID,
    seller: address,
    buyer: address,
    price: u64,
    commission: u64,
    beneficiary: address,
}

public struct MatchBidWithPurchaseCapEvent has copy, drop {
    bid_id: ID,
    nft_type: ascii::String,
    nft_id: ID,
    seller: address,
    seller_kiosk_id: ID,
    buyer: address,
    price: u64,
    commission: u64,
    beneficiary: address,
}

public struct MatchCollectionBidEvent has copy, drop {
    bid_id: ID,
    nft_type: ascii::String,
    nft_id: ID,
    seller: address,
    buyer: address,
    price: u64,
    commission: u64,
    beneficiary: address,
}

public struct MatchCollectionBidWithPurchaseCapEvent has copy, drop {
    bid_id: ID,
    nft_type: ascii::String,
    nft_id: ID,
    seller: address,
    seller_kiosk_id: ID,
    buyer: address,
    price: u64,
    commission: u64,
    beneficiary: address,
}

public struct ClaimEvent has copy, drop {
    nft_id: ID,
}

public struct ClaimWithPurchaseCapEvent has copy, drop {
    nft_id: ID,
    buyer: address,
    buyer_kiosk_id: ID,
}

#[allow(lint(self_transfer))]
public fun accept_bid<T: store + key>(
    store: &mut Store,
    id: ID, 
    store_kiosk_id: &mut kiosk::Kiosk, 
    user_kiosk_id: &mut kiosk::Kiosk, 
    kioskcap: &kiosk::KioskOwnerCap, 
    nft_id: ID, 
    policy: &transfer_policy::TransferPolicy<T>, 
    ctx: &mut TxContext
) : (coin::Coin<sui::SUI>, transfer_policy::TransferRequest<T>) {

    let selected_bid = if (dof::exists_with_type<ID, Bid>(&store.id, id)) {
        dof::remove<ID, Bid>(&mut store.id, id)
    } else {
        let bid_key = BidKey{bid_id: id};
        dof::remove<BidKey, Bid>(&mut store.id, bid_key)
    };

    let bid = selected_bid;
    let expected_nft_type = type_name::get<T>();
    assert!(*type_name::borrow_string(&expected_nft_type) == bid.nft_type, 1);

    let bid_nft_id = bid.nft_id;
    if (option::is_some<ID>(&bid_nft_id)) {
        assert!(*option::borrow<ID>(&bid_nft_id) == nft_id, 1);
    };
    
    let Bid {
        id          : bid_id,
        nft_type    : nft_type,
        nft_id      : _,
        buyer       : buyer,
        price       : price,
        wallet      : payment_coin,
        commission  : commission,
        beneficiary : beneficiary,
    } = bid;

    let mut  remaining_coin = payment_coin;
    object::delete(bid_id);

    transfer::public_transfer<coin::Coin<sui::SUI>>(
        coin::split<sui::SUI>(&mut remaining_coin, commission, ctx), 
        beneficiary
    );

    let purchase_cap = kiosk::list_with_purchase_cap<T>(
        user_kiosk_id, 
        kioskcap, 
        nft_id, 
        price, 
        ctx
    );

    let (purchased_item, transfer_request) = kiosk::purchase_with_cap<T>(
        user_kiosk_id, 
        purchase_cap, 
        coin::split<sui::SUI>(&mut remaining_coin, price, ctx));

    kiosk::lock<T>(
        store_kiosk_id, 
        &store.escrow_kiosk_cap, 
        policy, 
        purchased_item);

    let escrow = Escrow{
        id    : object::new(ctx), 
        buyer : buyer,
    };
    dof::add<ID, Escrow>(&mut store.id, nft_id, escrow);

    let seller = tx_context::sender(ctx);
    transfer::public_transfer<coin::Coin<sui::SUI>>(
        kiosk::withdraw(user_kiosk_id, kioskcap, option::none<u64>(), ctx), 
        seller
    );

    if (option::is_some<ID>(&bid_nft_id)) {
        let bid_event = MatchBidEvent{
            bid_id      : id, 
            nft_type    : nft_type, 
            nft_id      : nft_id, 
            seller      : seller, 
            buyer       : buyer, 
            price       : price, 
            commission  : commission, 
            beneficiary : beneficiary,
        };
        event::emit<MatchBidEvent>(bid_event);
    } else {
        let collection_bid_event = MatchCollectionBidEvent{
            bid_id      : id, 
            nft_type    : nft_type, 
            nft_id      : nft_id, 
            seller      : seller, 
            buyer       : buyer, 
            price       : price, 
            commission  : commission, 
            beneficiary : beneficiary,
        };
        event::emit<MatchCollectionBidEvent>(collection_bid_event);
    };
    (
        remaining_coin, 
        transfer_request
    )
}

public fun accept_bid_with_price_lock<T: store + key>(
    store: &mut Store, 
    id: ID, 
    store_kiosk_id: &mut kiosk::Kiosk, 
    kioskcap: &kiosk::KioskOwnerCap, 
    nft_id: ID, 
    ctx: &mut TxContext
) : (coin::Coin<sui::SUI>, transfer_policy::TransferRequest<T>) {

    let selected_bid = if (dof::exists_with_type<ID, Bid>(&store.id, id)) {
        dof::remove<ID, Bid>(&mut store.id, id)
    } else {
        let bid_key = BidKey{bid_id: id};
        dof::remove<BidKey, Bid>(&mut store.id, bid_key)
    };

    let bid = selected_bid;
    let expected_nft_type = type_name::get<T>();
    assert!(*type_name::borrow_string(&expected_nft_type) == bid.nft_type, 1);

    let bid_nft_id = bid.nft_id;
    if (option::is_some<ID>(&bid_nft_id)) {
        assert!(*option::borrow<ID>(&bid_nft_id) == nft_id, 1);
    };

    let Bid {
        id          : bid_id,
        nft_type    : nft_type,
        nft_id      : _,
        buyer       : buyer,
        price       : price,
        wallet      : payment_coin,
        commission  : commission,
        beneficiary : beneficiary,
    } = bid;

    let mut remaining_coin = payment_coin;
    object::delete(bid_id);

    transfer::public_transfer<coin::Coin<sui::SUI>>(
        coin::split<sui::SUI>(&mut remaining_coin, commission, ctx), 
        beneficiary
    );

    let escrow = EscrowWithPurchaseCap<T>{
        id           : object::new(ctx), 
        buyer        : buyer, 
        purchase_cap : kiosk::list_with_purchase_cap<T>(store_kiosk_id, kioskcap, nft_id, 0, ctx),
    };

    dof::add<ID, EscrowWithPurchaseCap<T>>(
        &mut store.id, 
        nft_id, 
        escrow
    );

    if (option::is_some<ID>(&bid_nft_id)) {
        let bid_event = MatchBidWithPurchaseCapEvent{
            bid_id          : id, 
            nft_type        : nft_type, 
            nft_id          : nft_id, 
            seller          : tx_context::sender(ctx), 
            seller_kiosk_id : object::id<kiosk::Kiosk>(store_kiosk_id), 
            buyer           : buyer, 
            price           : price, 
            commission      : commission, 
            beneficiary     : beneficiary,
        };
        event::emit<MatchBidWithPurchaseCapEvent>(bid_event);
    } else {
        let collection_bid_event = MatchCollectionBidWithPurchaseCapEvent{
            bid_id          : id, 
            nft_type        : nft_type, 
            nft_id          : nft_id, 
            seller          : tx_context::sender(ctx), 
            seller_kiosk_id : object::id<kiosk::Kiosk>(store_kiosk_id), 
            buyer           : buyer, 
            price           : price, 
            commission      : commission, 
            beneficiary     : beneficiary,
        };
        event::emit<MatchCollectionBidWithPurchaseCapEvent>(collection_bid_event);
    };
    (
        remaining_coin, 
        transfer_policy::new_request<T>(nft_id, price, object::id<kiosk::Kiosk>(store_kiosk_id))
    )
}

#[allow(lint(self_transfer))]
public fun accept_bid_with_purchase_cap<T: store + key>(
    store: &mut Store, 
    id: ID, 
    store_kiosk_id: &mut kiosk::Kiosk, 
    kioskcap: &kiosk::KioskOwnerCap, 
    nft_id: ID, 
    ctx: &mut TxContext
) : (coin::Coin<sui::SUI>, transfer_policy::TransferRequest<T>) {

    let selected_bid = if (dof::exists_with_type<ID, Bid>(&store.id, id)) {
        dof::remove<ID, Bid>(&mut store.id, id)
    } else {
        let bid_key = BidKey{bid_id: id};
        dof::remove<BidKey, Bid>(&mut store.id, bid_key)
    };

    let bid = selected_bid;
    let expected_nft_type = type_name::get<T>();
    assert!(*type_name::borrow_string(&expected_nft_type) == bid.nft_type, 1);

    let bid_nft_id = bid.nft_id;
    if (option::is_some<ID>(&bid_nft_id)) {
        assert!(*option::borrow<ID>(&bid_nft_id) == nft_id, 1);
    };

    let Bid {
        id          : bid_object_id,
        nft_type    : nft_type,
        nft_id      : _,
        buyer       : buyer,
        price       : price,
        wallet      : payment_coin,
        commission  : commission,
        beneficiary : beneficiary,
    } = bid;

    let mut remaining_coin = payment_coin;
    object::delete(bid_object_id);
    let seller = tx_context::sender(ctx);

    transfer::public_transfer<coin::Coin<sui::SUI>>(
        coin::split<sui::SUI>(&mut remaining_coin, commission, ctx), 
        beneficiary
    );

    transfer::public_transfer<coin::Coin<sui::SUI>>(
        coin::split<sui::SUI>(&mut remaining_coin, price, ctx), 
        seller
    );

    let escrow = EscrowWithPurchaseCap<T>{
        id           : object::new(ctx), 
        buyer        : buyer, 
        purchase_cap : kiosk::list_with_purchase_cap<T>(store_kiosk_id, kioskcap, nft_id, 0, ctx),
    };

    dof::add<ID, EscrowWithPurchaseCap<T>>(
        &mut store.id, 
        nft_id,
        escrow
    );

    transfer::public_transfer<coin::Coin<sui::SUI>>(
        kiosk::withdraw(store_kiosk_id, kioskcap, option::none<u64>(), ctx), 
        seller
    );

    if (option::is_some<ID>(&bid_nft_id)) {
        let bid_event = MatchBidWithPurchaseCapEvent{
            bid_id          : id, 
            nft_type        : nft_type, 
            nft_id          : nft_id, 
            seller          : seller, 
            seller_kiosk_id : object::id<kiosk::Kiosk>(store_kiosk_id), 
            buyer           : buyer, 
            price           : price, 
            commission      : commission, 
            beneficiary     : beneficiary,
        };
        event::emit<MatchBidWithPurchaseCapEvent>(bid_event);
    } else {
        let collection_bid_event = MatchCollectionBidWithPurchaseCapEvent{
            bid_id          : id, 
            nft_type        : nft_type, 
            nft_id          : nft_id, 
            seller          : seller, 
            seller_kiosk_id : object::id<kiosk::Kiosk>(store_kiosk_id), 
            buyer           : buyer, 
            price           : price, 
            commission      : commission, 
            beneficiary     : beneficiary,
        };
        event::emit<MatchCollectionBidWithPurchaseCapEvent>(collection_bid_event);
    };
    (
        remaining_coin, 
        transfer_policy::new_request<T>(nft_id, price, object::id<kiosk::Kiosk>(store_kiosk_id))
    )
}

#[allow(unused_type_parameter, unused_mut_parameter)]
entry fun admin_cancel_bid<T: store + key>(
    store: &mut Store, 
    id: ID, 
    ctx: &mut TxContext
) {
    assert!(tx_context::sender(ctx) == @0x619377d018b8b737ffdd47ebc23ba821e9e97c31a1c9883b5d9f5ff4f3aa2357, 0);

    let selected_bid = if (dof::exists_with_type<ID, Bid>(&store.id, id)) {
        dof::remove<ID, Bid>(&mut store.id, id)
    } else {
        let bid_key = BidKey{bid_id: id};
        dof::remove<BidKey, Bid>(&mut store.id, bid_key)
    };

    let Bid {
        id          : bid_object_id,
        nft_type    : nft_type,
        nft_id      : nft_id,
        buyer       : buyer,
        price       : price,
        wallet      : payment_coin,
        commission  : commission,
        beneficiary : beneficiary,
    } = selected_bid;

    let bid_nft_id = nft_id;
    object::delete(bid_object_id);

    transfer::public_transfer<coin::Coin<sui::SUI>>(
        payment_coin, 
        buyer
    );

    if (option::is_some<ID>(&bid_nft_id)) {
        let cancel_bid_event = CancelBidEvent{
            bid_id      : id, 
            nft_type    : nft_type, 
            nft_id      : *option::borrow<ID>(&bid_nft_id), 
            buyer       : buyer, 
            price       : price, 
            commission  : commission, 
            beneficiary : beneficiary,
        };
        event::emit<CancelBidEvent>(cancel_bid_event);
    } else {
        let cancel_collection_bid_event = CancelCollectionBidEvent{
            bid_id      : id, 
            nft_type    : nft_type, 
            buyer       : buyer, 
            price       : price, 
            commission  : commission, 
            beneficiary : beneficiary,
        };
        event::emit<CancelCollectionBidEvent>(cancel_collection_bid_event);
    };
}

public fun bid<T: store + key>(
    store: &mut Store, id: ID, 
    price: u64, 
    payment_coin: &mut coin::Coin<sui::SUI>, 
    commission: u64, 
    beneficiary: address, 
    ctx: &mut TxContext
) {
    bid_<T>(
        store, 
        option::some<ID>(id), 
        price, 
        payment_coin, 
        commission, 
        beneficiary, 
        ctx
    );
}

fun bid_<T: store + key>(
    store: &mut Store, 
    id: option::Option<ID>, 
    price: u64, 
    payment_coin: &mut coin::Coin<sui::SUI>, 
    commission: u64, 
    beneficiary: address, 
    ctx: &mut TxContext
) : ID {
    let remaining_coin = coin::value<sui::SUI>(payment_coin) - price + commission;
    assert!(remaining_coin >= 0, 1);

    let expected_nft_type = type_name::get<T>();
    let nft_type = *type_name::borrow_string(&expected_nft_type);
    let buyer = tx_context::sender(ctx);

    let bid = Bid{
        id          : object::new(ctx), 
        nft_type    : nft_type, 
        nft_id      : id, 
        buyer       : buyer, 
        price       : price, 
        wallet      : coin::split<sui::SUI>(payment_coin, price + commission + remaining_coin, ctx), 
        commission  : commission, 
        beneficiary : beneficiary,
    };

    let bid_id = object::id<Bid>(&bid);
    let bid_key = BidKey{bid_id: bid_id};
    dof::add<BidKey, Bid>(&mut store.id, bid_key, bid);

    if (option::is_some<ID>(&id)) {
        let create_bid_event = CreateBidEvent{
            bid_id      : bid_id, 
            nft_type    : nft_type, 
            nft_id      : *option::borrow<ID>(&id), 
            buyer       : buyer, 
            price       : price, 
            commission  : commission, 
            beneficiary : beneficiary,
        };
        event::emit<CreateBidEvent>(create_bid_event);
    } else {
        let create_collection_bid_event = CreateCollectionBidEvent{
            bid_id       : bid_id, 
            nft_type     : nft_type, 
            token_amount : 1, 
            buyer        : buyer, 
            price        : price, 
            commission   : commission, 
            beneficiary  : beneficiary,
        };
        event::emit<CreateCollectionBidEvent>(create_collection_bid_event);
    };
    bid_id
}

#[allow(unused_type_parameter)]
public fun cancel_bid<T: store + key>(
    store: &mut Store, 
    id: ID, 
    ctx: &mut TxContext
) {
    let selected_bid = if (dof::exists_with_type<ID, Bid>(&store.id, id)) {
        dof::remove<ID, Bid>(&mut store.id, id)
    } else {
        let bid_key = BidKey{bid_id: id};
        dof::remove<BidKey, Bid>(&mut store.id, bid_key)
    };

    let bid = selected_bid;
    assert!(tx_context::sender(ctx) == bid.buyer, 0);

    let Bid {
        id          : bid_id,
        nft_type    : nft_type,
        nft_id      : nft_id,
        buyer       : buyer,
        price       : price,
        wallet      : payment_coin,
        commission  : commission,
        beneficiary : beneficiary,
    } = bid;

    let bid_nft_id = nft_id;
    object::delete(bid_id);

    transfer::public_transfer<coin::Coin<sui::SUI>>(
        payment_coin, 
        buyer
    );

    if (option::is_some<ID>(&bid_nft_id)) {
        let cancel_bid_event = CancelBidEvent{
            bid_id      : id, 
            nft_type    : nft_type, 
            nft_id      : *option::borrow<ID>(&bid_nft_id), 
            buyer       : buyer, 
            price       : price, 
            commission  : commission, 
            beneficiary : beneficiary,
        };
        event::emit<CancelBidEvent>(cancel_bid_event);
    } else {
        let cancel_collection_bid_event = CancelCollectionBidEvent{
            bid_id      : id, 
            nft_type    : nft_type, 
            buyer       : buyer, 
            price       : price, 
            commission  : commission, 
            beneficiary : beneficiary,
        };
        event::emit<CancelCollectionBidEvent>(cancel_collection_bid_event);
    };
}

public fun claim_bid<T: store + key>(
    store: &mut Store, 
    store_kiosk_id: &mut kiosk::Kiosk, 
    user_kiosk_id: &mut kiosk::Kiosk, 
    kioskcap: &kiosk::KioskOwnerCap, 
    nft_id: ID, 
    policy: &transfer_policy::TransferPolicy<T>, 
    ctx: &mut TxContext
) : transfer_policy::TransferRequest<T> {

    let escrow = dof::remove<ID, Escrow>(
        &mut store.id, 
        nft_id
    );
    assert!(tx_context::sender(ctx) == escrow.buyer, 0);

    let Escrow {
        id    : escrow_id,
        buyer : _,
    } = escrow;
    object::delete(escrow_id);

    let purchase_cap = kiosk::list_with_purchase_cap<T>(
        store_kiosk_id, 
        &store.escrow_kiosk_cap, 
        nft_id, 
        0, 
        ctx
    );

    let (purchased_item, transfer_request) = kiosk::purchase_with_cap<T>(
        store_kiosk_id, 
        purchase_cap, 
        coin::zero<sui::SUI>(ctx)
    );

    kiosk::lock<T>(
        user_kiosk_id,
        kioskcap,
        policy,
        purchased_item
    );

    let claim_event = ClaimEvent{
        nft_id: nft_id
    };

    event::emit<ClaimEvent>(claim_event);
    transfer_request
}

public fun claim_bid_with_purchase_cap<T: store + key>(
    store: &mut Store, 
    store_kiosk_id: &mut kiosk::Kiosk, 
    user_kiosk_id: &mut kiosk::Kiosk, 
    kioskcap: &kiosk::KioskOwnerCap, 
    nft_id: ID, 
    policy: &transfer_policy::TransferPolicy<T>, 
    ctx: &mut TxContext
) : transfer_policy::TransferRequest<T> {

    let escrow = dof::remove<ID, EscrowWithPurchaseCap<T>>(
        &mut store.id, 
        nft_id
    );
    assert!(tx_context::sender(ctx) == escrow.buyer, 0);

    let EscrowWithPurchaseCap {
        id           : escrow_id,
        buyer        : buyer,
        purchase_cap : purchasecap,
    } = escrow;
    object::delete(escrow_id);

    let (purchased_item, transfer_request) = kiosk::purchase_with_cap<T>(
        store_kiosk_id, 
        purchasecap, 
        coin::zero<sui::SUI>(ctx)
    );

    kiosk::lock<T>(
        user_kiosk_id, 
        kioskcap, 
        policy, 
        purchased_item
    );

    let claim_event = ClaimWithPurchaseCapEvent{
        nft_id         : nft_id, 
        buyer          : buyer, 
        buyer_kiosk_id : object::id<kiosk::Kiosk>(user_kiosk_id),
    };
    event::emit<ClaimWithPurchaseCapEvent>(claim_event);
    transfer_request
}

public fun collection_bid<T: store + key>(
    store: &mut Store, 
    price: u64, 
    payment_coin: &mut coin::Coin<sui::SUI>, 
    commission: u64, 
    beneficiary: address, 
    ctx: &mut TxContext
) {
    bid_<T>(
        store, 
        option::none<ID>(), 
        price, 
        payment_coin, 
        commission, 
        beneficiary, 
        ctx
    );
}

fun init(ctx: &mut TxContext) {
    let (kiosk, kioskcap) = kiosk::new(ctx);
    transfer::public_share_object<kiosk::Kiosk>(kiosk);
    let store = Store{
        id               : object::new(ctx), 
        escrow_kiosk_cap : kioskcap,
    };
    transfer::share_object<Store>(store);
}
