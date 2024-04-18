/// Module: bookshop
module bookshop::bookshop {
    //==============================================================================================
    //                                  Dependencies
    //==============================================================================================
    use sui::tx_context::{Self, TxContext, sender};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::clock::{Self, Clock, timestamp_ms};
    use std::string::{Self, String};
    use sui::dynamic_object_field as dof;
    use sui::dynamic_field as df;


    //==============================================================================================
    //                                  Constants
    //==============================================================================================
    const BOOK_STATE_ON_SALE: u8 = 1;
    const BOOK_STATE_OFF_SALE: u8 = 2;

    //==============================================================================================
    //                                  Error codes
    //==============================================================================================
    const EBookNameInvalid: u64 = 1;
    const EBuyBookSuiNotEnough: u64 = 2;
    const EBookNotOnSale: u64 = 3;
    const EBookAmountNotEnough: u64 = 4;
    const EBookBuyAmountInvalid: u64 = 5;
    const EBookBuySuiAmountInvalid: u64 = 6;
    const EBookNameNotChanged: u64 = 7;
    const EBookPriceNotChanged: u64 = 8;
    const EBookCountNotChanged: u64 = 9;
    const EBookStateNotChanged: u64 = 10;

    //==============================================================================================
    //                                  Module structs
    //==============================================================================================

    /*
        AdminCap is the capability for admin role management
    */
    public struct AdminCap has key {
        id: UID,
    }

    /*
        BOOKSHOP is the one time witness for module init
    */
    public struct BOOKSHOP has drop {
    }

    public struct Item has store, copy, drop { id: ID }

    public struct Listing has store, copy, drop { id: ID, is_exclusive: bool }

    /*
        ShopInfo manages the shop informations, now contains the payment address for consumers
        - id: the unique id of the ShopInfo
        - pay_adderss: payment address
    */
    public struct Shop has key {
        id: UID,
        owner: address,
        item_count: u64,
        balance: Balance<SUI>
    }

    /*
        Book for consumers when they bought books
        - id: the unique id of the Book
        - book_id: the unique id of the BookInfo
        - book_count: the count of books
        - create_at: book nft created timestamp
    */
    public struct Book has key, store {
        id: UID,
        inner: ID,
        name: String,
        price: u64,
        count: u64,
        create_at: u64,
        update_at: u64,
        state: u8,
    }

    //==============================================================================================
    //                                  Event structs
    //==============================================================================================
    
    /*
        Event emitted when update book name event happened.
            - book_id: the id of the bookinfo.
            - oldname: book old name.
            - name: book name.
    */
    public struct UpdateBookNameEvent has copy, drop {
        book_id: ID,
        oldname: String,
        name: String,
    }

    /*
        Event emitted when update book price event happened.
            - book_id: the id of the bookinfo.
            - oldprice: book old price.
            - price: book price.
    */
    public struct UpdateBookPriceEvent has copy, drop {
        book_id: ID,
        oldprice: u64,
        price: u64,
    }

    /*
        Event emitted when update book count event happened.
            - book_id: the id of the bookinfo.
            - oldcount: book old count.
            - count: book count.
    */
    public struct UpdateBookCountEvent has copy, drop {
        book_id: ID,
        oldcount: u64,
        count: u64,
    }

    /*
        Event emitted when update book state event happened.
            - book_id: the id of the bookinfo.
            - oldstate: book old state.
            - state: book state.
    */
    public struct UpdateBookStateEvent has copy, drop {
        book_id: ID,
        oldstate: u8,
        state: u8,
    }

    /*
        Event emitted when buy book event happened.
            - book_id: the id of the bookinfo.
            - book_count: buy book amount.
            - create_at: buy book timestamp.
    */
    public struct BuyBookEvent has copy, drop {
        book_id: ID,
        book_count: u64,
        create_at: u64,
    }

    //==============================================================================================
    //                                      Functions
    //==============================================================================================
    /*
        init function for module init
        transfer AdminCap to the admin
        make ShopInfo share object
    */
    fun init(_otw: BOOKSHOP, ctx: &mut TxContext) {
        let admin_address = tx_context::sender(ctx);
        let admin_cap = AdminCap {
            id: object::new(ctx)
        };
        transfer::transfer(admin_cap, admin_address);

        let shop = Shop {
            id: object::new(ctx),
            owner: sender(ctx),
            item_count:0,
            balance: balance::zero()
        };
        transfer::share_object(shop);
    }

    /*
        update book name, it will emit AddBookEvent event
        @param adminCap: the admin role capability controll
        @param name: book name
        @param clock: clock for timestamp
        @param ctx: The transaction context.
    */
    public fun new_name(self: &mut Book, name: String, clock: &Clock, ctx: &mut TxContext) {
        self.name = name;
        self.update_at = timestamp_ms(clock);
    }

    /*
        update book price, it will emit UpdateBookPriceEvent event
        @param adminCap: the admin role capability controll
        @param bookinfo: bookinfo struct
        @param price: book price
        @param clock: clock for timestamp
        @param ctx: The transaction context.
    */
    public fun new_price(self: &mut Book, price: u64, clock: &Clock, _ctx: &mut TxContext) {
        assert!(self.price != price, EBookPriceNotChanged);
        self.price = price;
        self.update_at = clock::timestamp_ms(clock);
    }

    // /*
    //     update book state on sale, it will emit UpdateBookStateEvent event
    //     @param adminCap: the admin role capability controll
    //     @param bookinfo: bookinfo struct
    //     @param clock: clock for timestamp
    //     @param ctx: The transaction context.
    // */
    public fun list(_: &AdminCap, self: &mut Shop, book: Book, price: u64) {
        let id_ = book.inner;
        place_internal(self, book);

        df::add(&mut self.id, Listing { id: id_, is_exclusive: false }, price);
    }

    /*
        update book state off sale, it will emit UpdateBookStateEvent event
        @param adminCap: the admin role capability controll
        @param bookinfo: bookinfo struct
        @param clock: clock for timestamp
        @param ctx: The transaction context.
    */
    public fun delist(_: &AdminCap, self: &mut Shop, id: ID) {
        df::remove<Listing, u64>(&mut self.id, Listing { id, is_exclusive: false });
    }

    /*
        buy book function, it will emit BuyBookEvent event
        @param shopInfo: ShopInfo struct
        @param bookinfo: bookinfo struct
        @param sui: sui payed to buy book
        @param amount: buy book amount
        @param clock: clock for timestamp
        @param ctx: The transaction context.
    */
    public fun purchase(self: &mut Shop, id: ID, payment: Coin<SUI>) : Book {
        let price = df::remove<Listing, u64>(&mut self.id, Listing { id, is_exclusive: false });
        let item = dof::remove<Item, Book>(&mut self.id, Item { id });

        self.item_count = self.item_count - 1;
        assert!(price == payment.value(), EBookBuyAmountInvalid);
        coin::put(&mut self.balance, payment);

        item
    }

    public fun withdraw_profits(_: &AdminCap, self: &mut Shop, amount: u64, ctx: &mut TxContext) : Coin<SUI> {
        coin::take(&mut self.balance, amount, ctx)
    }

    /*
        get shop payment address
        @param shopInfo: ShopInfo struct
        @return : payment address.
    */
    public fun GetShopInfoPayAddress(self: &Shop): address {
        self.owner
    }

    /*
        get book nft count
        @param Book: Book struct
        @return : book nft count.
    */
    public fun GetBookCount(self: &Book): u64 {
        self.price
    }

    /*
        get book nft id
        @param Book: Book struct
        @return : book nft id.
    */
    public fun GetBookId(self: &Book): ID {
        self.inner
    }

    fun place_internal(self: &mut Shop, book: Book) {
        self.item_count = self.item_count + 1;
        dof::add(&mut self.id, Item { id: object::id(&book) }, book)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(BOOKSHOP {}, ctx);
    }
}

