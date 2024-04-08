module house_renting::house_renting{
    // === Imports ===
    use std::string::{Self,String};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::object::{Self,UID, ID};
    use sui::tx_context::{Self,TxContext, sender};
    use sui::transfer;
    use sui::table::{Table, Self};
    use sui::bag::{Self, Bag};
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::kiosk_extension::{Self as ke};
    use sui::transfer_policy::{Self as tp};
    use sui::package::{Self, Publisher};


    // === Constants ===
    //There is no damage to the house
    const DAMAGE_LEVEL_UNKNOWN: u8 = 0;
    const DAMAGE_LEVEL_0: u8 = 1;
    //The house is slightly damaged and requires a 10% deposit compensation
    const DAMAGE_LEVEL_1: u8 = 2;
    //The house is moderately damaged and requires a 50% deposit compensation
    const DAMAGE_LEVEL_2: u8 = 3;
    //The house is severely damaged and requires compensation for all deposits
    const DAMAGE_LEVEL_3: u8 = 4;

    //The administrator has not yet reviewed the inspection report
    const WAITING_FOR_REVIEW: u8 = 0;
    //The administrator has reviewed the inspection report
    const REVIEWED: u8 = 1;

    // percent of deposit to monthly rent
    const DEPOSIT_PERCENT: u64 = 50;
    

    // === Errors ===
    const ETenancyIncorrect: u64 = 1;
    const EInvalidSuiAmount: u64 = 2;
    const EDamageIncorrect: u64 = 3;
    const ENoPermission: u64 = 4;
    const EWrongParams: u64 = 5;
    const EInspectionReviewed: u64 = 6;
    const EInvalidNotice: u64 = 7;



    // === Structs ===
    // This is a platform for landlords to post rentals and tenants to rent apartments.  
    struct RentalPlatform has key,store {
        // uid of the RentalPlatform object
        id: UID,
        // deposit stored on the rental platform, key is house object id
        deposit_pool: Table<ID, Coin<SUI>>,
        // rental notices on the platform, key is house object id
        notices: Table<ID, RentalNotice>,
        //owner of platform
        owner: address,
    }

    //presents Rental platform administrator
    struct Admin has key, store {
        // uid of admin object
        id: UID,
    }

    //If the landlord wants to rent out a house, they first need to issue a rental notice
    struct RentalNotice has key,store  {
        // uid of the RentalNotice object
        id: UID,
        // the amount of gas to be paid per month
        monthly_rent: u64,
        // the amount of gas to be deposited 
        deposit: u64,
        // the id of the house object
        house_id: ID,
        // account address of landlord
        landlord: address,
    }

    // present a house object
    struct House has key {
        // uid of the house object
        id: UID,
        // The square of the house area
        area: u64,
        // The owner of the house
        owner: address,
        // A set of house photo links
        photo: String,
        // The landlord's description of the house
        description: String
    }

    // present a house rentle contract object
    struct Lease has key,store {
        // uid of the Lease object
        id: UID,
        //uid of house object
        house_id: ID,
        // Tenant's account address
        tenant: address,
        // Landlord's account address
        landlord: address,
        // The month plan to rent
        tenancy: u32,
        // The mount of gas already paid
        paid_rent: u64,
        // The mount of gas already paid for deposit
        paid_deposit: u64,
    }

    //presents inspection report object.The landlord submits the inspection report, and the administrator reviews the inspection report
    struct Inspection has key,store {
        // uid of the Inspection object
        id: UID,
        //id of the house object
        house_id: ID,
        //id of the lease object
        lease_id: ID,
        //Damage level, from 0 to 3, evaluated by the landlord
        damage: u8,
        //Description of damage details submitted by the landlord
        damage_description: String,
        //Photos of the damaged area submitted by the landlord
        damage_photo: String,
        //Damage level evaluated by administrator
        damage_assessment_ret: u8,
        //Deducting the deposit based on the damage to the house
        deduct_deposit: u64,
        //Used to mark whether the administrator reviews or not
        review_status: u8,
    }

    /// Publisher capability object
    struct HousePublisher has key { id: UID, publisher: Publisher }

     // one time witness 
    struct HOUSE_RENTING has drop {}

    // kiosk_extension witness
    struct HouseKioskExtWitness has drop {}

    // =================== Initializer ===================
    fun init(otw: HOUSE_RENTING, ctx: &mut TxContext) {
        // define the publisher
        let publisher_ = package::claim<HOUSE_RENTING>(otw, ctx);
        // wrap the publisher and share.
        transfer::share_object(HousePublisher {
            id: object::new(ctx),
            publisher: publisher_
        }); 
    }

    // === Public-Mutative Functions ===

    /// Users can create new kiosk for marketplace 
    public fun new(ctx: &mut TxContext) {
        let(kiosk, kiosk_cap) = kiosk::new(ctx);
        // share the kiosk
        let witness = HouseKioskExtWitness {};
        // create and extension for using bag
        ke::add<HouseKioskExtWitness>(witness, &mut kiosk, &kiosk_cap, 00, ctx);
        transfer::public_share_object(kiosk);
        // you can send the cap with ptb
        transfer::public_transfer(kiosk_cap, sender(ctx));
    }
    // create any transferpolicy for rules 
    public fun new_policy(publish: &HousePublisher, ctx: &mut TxContext ) {
        // set the publisher
        let publisher = get_publisher(publish);
        // create an transfer_policy and tp_cap
        let (transfer_policy, tp_cap) = tp::new<House>(publisher, ctx);
        // transfer the objects 
        transfer::public_transfer(tp_cap, tx_context::sender(ctx));
        transfer::public_share_object(transfer_policy);
    }

    //The landlord releases a rental message, creates a house object,and transfer.
    public entry fun post_rental_notice_and_transfer(platform: &mut Kiosk, monthly_rent: u64, housing_area: u64, description: vector<u8>, photo: vector<u8>, ctx: &mut TxContext){
        let house = post_rental_notice(platform, monthly_rent, housing_area, description, photo, ctx);
        transfer::transfer(house, tx_context::sender(ctx));
    }

    //call pay_rent function,transfer coin object to landlord
    public entry fun pay_rent_and_transfer(platform: &mut Kiosk, house_address: address, tenancy: u32,  paid: Coin<SUI>, ctx: &mut TxContext) {
        let house_id: ID = object::id_from_address(house_address);
        let (paid, landlord) = pay_rent(platform, house_id, tenancy, paid, ctx);
        transfer::public_transfer(paid, landlord);
    }
    
    //After the tenant pays the rent, the landlord transfers the house to the tenant
    public entry fun transfer_house_to_tenant(lease: &Lease, house: House) {
        transfer::transfer(house, lease.tenant)
    }
    
    //Rent expires, landlord inspects and submits inspection report
    public entry fun landlord_inspect(lease: &Lease, damage: u8, damage_description: vector<u8>, damage_photo: vector<u8>, ctx: &mut TxContext) {
        assert!(lease.landlord == tx_context::sender(ctx), ENoPermission);
        assert!(damage >= DAMAGE_LEVEL_0 && damage <= DAMAGE_LEVEL_3, EDamageIncorrect);
        let inspection = Inspection{
            id: object::new(ctx),
            house_id: lease.house_id,
            lease_id: object::uid_to_inner(&lease.id),
            damage: damage,
            damage_description: string::utf8(damage_description),
            damage_photo: string::utf8(damage_photo),
            damage_assessment_ret: DAMAGE_LEVEL_UNKNOWN,
            deduct_deposit: 0,
            review_status: WAITING_FOR_REVIEW
        };

        transfer::public_share_object(inspection);
    }

    //The platform administrator reviews the inspection report and return a coin of  deposit
    public entry fun review_inspection_report( _: &KioskOwnerCap, platform: &mut Kiosk, lease: &Lease, inspection: &mut Inspection, damage: u8, ctx: &mut TxContext)  {
        assert!(lease.house_id == inspection.house_id, EWrongParams);
        assert!(inspection.review_status == WAITING_FOR_REVIEW, EInspectionReviewed);
        assert!(damage >= DAMAGE_LEVEL_0 && damage <= DAMAGE_LEVEL_3, EDamageIncorrect);

        let deduct_deposit:u64 = calculate_deduct_deposit(lease.paid_deposit, damage);

        inspection.damage_assessment_ret = damage;
        inspection.review_status = REVIEWED;
        inspection.deduct_deposit = deduct_deposit;

        if (deduct_deposit > 0) {
             // define the witness
            let witness = HouseKioskExtWitness {};
            let owner_bag = ke::storage_mut<HouseKioskExtWitness>(witness, platform);

            let coin = coin::split(
                bag::borrow_mut<ID, Coin<SUI>>(owner_bag, lease.house_id),
                deduct_deposit,
                ctx,
            );
            transfer::public_transfer(coin, lease.landlord);
        }
    }

    //The tenant returns the room to the landlord , receives the deposit
    public entry fun tenant_return_house_and_transfer(platform: &mut Kiosk, lease: &Lease, house: House, ctx: &mut TxContext) {
        let (deposit, house) = tenant_return_house(platform, lease, house, ctx);
         if (coin::value(&deposit) > 0) {
               transfer::public_transfer(deposit, tx_context::sender(ctx)); 
        } else {
            coin::destroy_zero<SUI>(deposit);
        };
        transfer::transfer(house, lease.landlord)
    }

    //The landlord releases a rental message, creates a rentalnotice object and create a house object
    public fun post_rental_notice(platform: &mut Kiosk, monthly_rent: u64, housing_area: u64, description: vector<u8>, photo: vector<u8>, ctx: &mut TxContext): House {
        //caculate deposit by monthly_rent
        let deposit = (monthly_rent * DEPOSIT_PERCENT) / 100;
        
        let house = House {
            id: object::new(ctx),
            area: housing_area,
            owner: tx_context::sender(ctx),
            photo: string::utf8(photo),
            description:string::utf8(description),
        };
        let rentalnotice = RentalNotice{
            id: object::new(ctx),
            deposit: deposit,
            monthly_rent: monthly_rent,
            house_id: object::uid_to_inner(&house.id),
            landlord: tx_context::sender(ctx),
        };
         // define the witness
        let witness = HouseKioskExtWitness {};
        let owner_bag = ke::storage_mut<HouseKioskExtWitness>(witness, platform);
        bag::add<ID,RentalNotice>( owner_bag, object::uid_to_inner(&house.id), rentalnotice);
        house
    }

    //Tenants pay rent and sign rental contracts
    public fun pay_rent(platform: &mut Kiosk, house_id: ID, tenancy: u32,  paid: Coin<SUI>, ctx: &mut TxContext): (Coin<SUI>, address) {
        assert!(tenancy > 0, ETenancyIncorrect);

        // define the witness
        let witness = HouseKioskExtWitness {};
        // get bag 
        let owner_bag = ke::storage_mut<HouseKioskExtWitness>(witness, platform);  
        // get notice 
        let RentalNotice{id: notice_id, monthly_rent: monthly_rent_, deposit: deposit_, house_id: house_id_, landlord: landlord } = bag::remove<ID, RentalNotice>(owner_bag, house_id);        
        let rent = monthly_rent_ * (tenancy as u64);
        let total_fee = rent + deposit_;
        assert!(total_fee == coin::value(&paid), EInvalidSuiAmount);
        
        //the deposit is stored by rental platform
        let deposit_coin = coin::split<SUI>(&mut paid, deposit_, ctx);
        bag::add(owner_bag, house_id, deposit_coin);
        
        //lease is a Immutable object
        let lease_ = Lease {
            id: object::new(ctx),
            tenant: tx_context::sender(ctx),
            landlord: landlord,
            tenancy: tenancy,
            paid_rent: rent,
            paid_deposit: deposit_,
            house_id: house_id_,
        };

        transfer::public_freeze_object(lease_);
        object::delete(notice_id);

        (paid, landlord)
    }
  
    //The tenant returns the room to the landlord and receives the deposit
    public fun tenant_return_house(platform: &mut Kiosk, lease: &Lease, house: House, ctx: &mut TxContext): (Coin<SUI>, House) {
        assert!(lease.house_id == object::uid_to_inner(&house.id), EWrongParams);
        assert!(lease.tenant == tx_context::sender(ctx), ENoPermission);

        // define the witness
        let witness = HouseKioskExtWitness {};
        let owner_bag = ke::storage_mut<HouseKioskExtWitness>(witness, platform);

        let deposit = bag::remove<ID, Coin<SUI>>(owner_bag, lease.house_id);
       
        (deposit, house)
    }

    // return the publisher
    fun get_publisher(shared: &HousePublisher) : &Publisher {
        &shared.publisher
     }

    // === Private Functions ===
    fun calculate_deduct_deposit(paid_deposit: u64, damage: u8): u64 {
        //Deducting the tenant's deposit as compensation for damaged property
        let deduct_deposit:u64 = 0;
        //The house is slightly damaged and requires a 10% deposit compensation
        if (DAMAGE_LEVEL_1 == damage) {
            deduct_deposit = paid_deposit /10 * 1; 
        };
        //The house is moderately damaged and requires a 50% deposit compensation
        if (DAMAGE_LEVEL_2 == damage) {
            deduct_deposit = paid_deposit / 10 * 5; 
        };
        //The house is severely damaged and requires compensation for all deposits
        if (DAMAGE_LEVEL_3 == damage) {
            deduct_deposit = paid_deposit; 
        };
        deduct_deposit
    }
}
