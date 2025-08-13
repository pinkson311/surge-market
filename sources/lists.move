module surge::lists;

use sui::kiosk;
use sui::coin;
use sui::dynamic_object_field as dof;
use sui::sui;
use sui::event;

public struct Store has key {
    id: UID,
}

public struct Listing<phantom T: store + key> has store, key {
    id: UID,
    seller: address,
    kiosk_id: ID,
    nft_id: ID,
    cap: kiosk::PurchaseCap<T>,
    price: u64,
    commission: u64,
    beneficiary: address,
}

public struct ListEvent has copy, drop {
    listing_id: ID,
    seller: address,
    kiosk_id: ID,
    nft_id: ID,
    price: u64,
    commission: u64,
    beneficiary: address,
}

public struct UnlistEvent has copy, drop {
    listing_id: ID,
    seller: address,
    kiosk_id: ID,
    nft_id: ID,
    price: u64,
    commission: u64,
    beneficiary: address,
}

public struct BuyEvent has copy, drop {
    listing_id: ID,
    seller: address,
    seller_kiosk_id: ID,
    buyer: address,
    buyer_kiosk_id: ID,
    nft_id: ID,
    price: u64,
    commission: u64,
    beneficiary: address,
}

public fun buy<T: store + key>(
    store: &mut Store, 
    seller_kiosk_id: &mut kiosk::Kiosk, 
    buyer_kiosk_id: &mut kiosk::Kiosk, 
    nft_id: ID, 
    payment_coin: &mut coin::Coin<0x2::sui::SUI>, 
    ctx: &mut TxContext
) : (T, 0x2::transfer_policy::TransferRequest<T>, u64) {

    let listing = dof::remove<ID, Listing<T>>(&mut store.id, nft_id);
    assert!(coin::value<sui::SUI>(payment_coin) == listing.price, 1);

    let listing_id = object::id<Listing<T>>(&listing);
    let Listing {
        id          : listing_object_id,
        seller      : seller,
        kiosk_id    : _,
        nft_id      : _,
        cap         : purchasecap,
        price       : price,
        commission  : commission,
        beneficiary : beneficiary,
    } = listing;
    object::delete(listing_object_id);

    transfer::public_transfer<coin::Coin<sui::SUI>>(
        coin::split<sui::SUI>(payment_coin, commission, ctx), 
        beneficiary
    );

    let seller_amount = price - commission;
    let (purchased_item, transfer_request) = kiosk::purchase_with_cap<T>(
        seller_kiosk_id, 
        purchasecap, 
        coin::split<sui::SUI>(payment_coin, seller_amount, ctx)
    );

    let buy_event = BuyEvent{
        listing_id      : listing_id, 
        seller          : seller, 
        seller_kiosk_id : object::id<kiosk::Kiosk>(seller_kiosk_id), 
        buyer           : tx_context::sender(ctx), 
        buyer_kiosk_id  : object::id<kiosk::Kiosk>(buyer_kiosk_id), 
        nft_id          : nft_id, 
        price           : price, 
        commission      : commission, 
        beneficiary     : beneficiary,
    };
    event::emit<BuyEvent>(buy_event);
    (purchased_item, transfer_request, seller_amount)
}

fun init(ctx: &mut TxContext) {
    let store = Store{id: 0x2::object::new(ctx)};
    transfer::share_object<Store>(store);
}

public fun list<T: store + key>(
    store: &mut Store, 
    seller_kiosk_id: &mut kiosk::Kiosk, 
    kioskcap: &kiosk::KioskOwnerCap, 
    nft_id: ID, 
    price: u64, 
    commission: u64, 
    beneficiary: address, 
    ctx: &mut TxContext
) {
    assert!(commission < price, 1);
    let seller = tx_context::sender(ctx);
    let kiosk_id = object::id<kiosk::Kiosk>(seller_kiosk_id);

    let listing = Listing<T>{
        id          : object::new(ctx), 
        seller      : seller, 
        kiosk_id    : kiosk_id, 
        nft_id      : nft_id, 
        cap         : kiosk::list_with_purchase_cap<T>(seller_kiosk_id, kioskcap, nft_id, price - commission, ctx), 
        price       : price, 
        commission  : commission, 
        beneficiary : beneficiary,
    };

    let listing_id = object::id<Listing<T>>(&listing);
    dof::add<0x2::object::ID, Listing<T>>(
        &mut store.id, 
        nft_id, 
        listing
    );

    let list_event = ListEvent{
        listing_id  : listing_id, 
        seller      : seller, 
        kiosk_id    : kiosk_id, 
        nft_id      : nft_id, 
        price       : price, 
        commission  : commission, 
        beneficiary : beneficiary,
    };
    event::emit<ListEvent>(list_event);
}

#[allow(unused_variable)]
public fun unlist<T: store + key>(
    store: &mut Store, 
    seller_kiosk_id: &mut kiosk::Kiosk, 
    kioskcap: &kiosk::KioskOwnerCap, 
    nft_id: ID, 
    ctx: &mut TxContext
) {
    assert!(kiosk::has_access(seller_kiosk_id, kioskcap), 0);

    let listing = dof::remove<ID, Listing<T>>(
        &mut store.id, 
        nft_id
    );

    let listing_id = object::id<Listing<T>>(&listing);
    let Listing {
        id          : listing_object_id,
        seller      : seller,
        kiosk_id    : kiosk_id,
        nft_id      : _,
        cap         : purchasecap,
        price       : price,
        commission  : commission,
        beneficiary : beneficiary,
    } = listing;

    object::delete(listing_object_id);
    kiosk::return_purchase_cap<T>(seller_kiosk_id, purchasecap);

    let unlist_event = UnlistEvent{
        listing_id  : listing_id, 
        seller      : seller, 
        kiosk_id    : kiosk_id, 
        nft_id      : nft_id, 
        price       : price, 
        commission  : commission, 
        beneficiary : beneficiary,
    };
    event::emit<UnlistEvent>(unlist_event);
}
