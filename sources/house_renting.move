module house_renting::house_renting{
    // === Imports ===
    use std::string::{Self,String};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::object::{Self,UID, ID};
    use sui::tx_context::{Self,TxContext};
    use sui::transfer;
    use sui::table::{Table, Self};


    // === Constants ===
    //There is no damage to the house
    const DAMAGE_LEVEL_UNKOWN: u8 = 0;
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
    struct House has key,store {
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


    // === Public-Mutative Functions ===
    //call new_platform function .then transfer admin object
    public entry fun new_platform_and_transfer(ctx: &mut TxContext) {
        let admin = new_platform(ctx);

        transfer::public_transfer(admin, tx_context::sender(ctx))
    }

    //The landlord releases a rental message, creates a house object,and transfer.
    public entry fun post_rental_notice_and_transfer(platform: &mut RentalPlatform, monthly_rent: u64, housing_area: u64, description: vector<u8>, photo: vector<u8>, ctx: &mut TxContext){
        let house = post_rental_notice(platform, monthly_rent, housing_area, description, photo, ctx);
        transfer::public_transfer(house, tx_context::sender(ctx));
    }

    //call pay_rent function,transfer coin object to landlord
    public entry fun pay_rent_and_transfer(platform: &mut RentalPlatform, house_address: address, tenancy: u32,  paid: Coin<SUI>, ctx: &mut TxContext) {
        let house_id: ID = object::id_from_address(house_address);
        let (paid, landlord) = pay_rent(platform, house_id, tenancy, paid, ctx);
        transfer::public_transfer(paid, landlord);
    }
    
    //After the tenant pays the rent, the landlord transfers the house to the tenant
    public entry fun transfer_house_to_tenant(lease: &Lease, house: House) {
        transfer::public_transfer(house, lease.tenant)
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
            damage_assessment_ret: DAMAGE_LEVEL_UNKOWN,
            deduct_deposit: 0,
            review_status: WAITING_FOR_REVIEW
        };

        transfer::public_share_object(inspection);
    }

    //The platform administrator reviews the inspection report and return a coin of  deposit
    public entry fun review_inspection_report(platform: &mut RentalPlatform, lease: &Lease, inspection: &mut Inspection, damage: u8, _: &Admin, ctx: &mut TxContext)  {
        assert!(lease.house_id == inspection.house_id, EWrongParams);
        assert!(inspection.review_status == WAITING_FOR_REVIEW, EInspectionReviewed);
        assert!(damage >= DAMAGE_LEVEL_0 && damage <= DAMAGE_LEVEL_3, EDamageIncorrect);

        let deduct_deposit:u64 = caculate_deduct_deposit(lease.paid_deposit, damage);

        inspection.damage_assessment_ret = damage;
        inspection.review_status = REVIEWED;
        inspection.deduct_deposit = deduct_deposit;

        if (deduct_deposit > 0) {
            let coin = coin::split(
                table::borrow_mut<ID, Coin<SUI>>(&mut platform.deposit_pool, lease.house_id),
                deduct_deposit,
                ctx,
            );
            transfer::public_transfer(coin, lease.landlord);
        }
    }

    //The tenant returns the room to the landlord , receives the deposit
    public entry fun tenant_return_house_and_transfer(platform: &mut RentalPlatform, lease: &Lease, house: House, ctx: &mut TxContext) {
        let (deposit, house) = tenant_return_house(platform, lease, house, ctx);
         if (coin::value(&deposit) > 0) {
               transfer::public_transfer(deposit, tx_context::sender(ctx)); 
        } else {
            coin::destroy_zero<SUI>(deposit);
        };
        transfer::public_transfer(house, lease.landlord)
    }
    // create a new rentle platform object and initializes its fields.
    public fun new_platform(ctx: &mut TxContext): Admin {
        let platform = RentalPlatform {
            id: object::new(ctx),
            deposit_pool: table::new<ID, Coin<SUI>>(ctx),
            notices: table::new<ID, RentalNotice>(ctx),
            owner: tx_context::sender(ctx),
        };
    
        transfer::public_share_object(platform);

        Admin {
            id: object::new(ctx),
        }
    }

    //The landlord releases a rental message, creates a rentalnotice object and create a  house object
    public fun post_rental_notice(platform: &mut RentalPlatform, monthly_rent: u64, housing_area: u64, description: vector<u8>, photo: vector<u8>, ctx: &mut TxContext): House {
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

        table::add<ID, RentalNotice>(&mut platform.notices, object::uid_to_inner(&house.id), rentalnotice);

        house
    }

    //Tenants pay rent and sign rental contracts
    public fun pay_rent(platform: &mut RentalPlatform, house_id: ID, tenancy: u32,  paid: Coin<SUI>, ctx: &mut TxContext): (Coin<SUI>, address) {
        assert!(tenancy > 0, ETenancyIncorrect);
        assert!(table::contains<ID, RentalNotice>(&platform.notices, house_id), EInvalidNotice);

        let notice = table::borrow<ID, RentalNotice>(&platform.notices, house_id);
        let rent = notice.monthly_rent * (tenancy as u64);
        let total_fee = rent + notice.deposit;
        assert!(total_fee == coin::value(&paid), EInvalidSuiAmount);
        
        //the deposit is stored by rental platform
        let deposit_coin = coin::split<SUI>(&mut paid, notice.deposit, ctx);
        if (table::contains<ID, Coin<SUI>>(&platform.deposit_pool, notice.house_id)) {
            coin::join(
                table::borrow_mut<ID, Coin<SUI>>(&mut platform.deposit_pool, notice.house_id),
                deposit_coin
            )
        } else {
            table::add(&mut platform.deposit_pool, notice.house_id, deposit_coin)
        };
        
        //lease is a Immutable object
        let lease = Lease {
            id: object::new(ctx),
            tenant: tx_context::sender(ctx),
            landlord: notice.landlord,
            tenancy: tenancy,
            paid_rent: rent,
            paid_deposit: notice.deposit,
            house_id: notice.house_id,
        };
        transfer::public_freeze_object(lease);

        //remove notice from platform
        let RentalNotice{id: notice_id, monthly_rent: _, deposit: _, house_id: _, landlord: landlord } = table::remove<ID, RentalNotice>(&mut platform.notices, house_id);
        object::delete(notice_id);


        (paid, landlord)
    }
  
    //The tenant returns the room to the landlord and receives the deposit
    public fun tenant_return_house(platform: &mut RentalPlatform, lease: &Lease, house: House, ctx: &mut TxContext): (Coin<SUI>, House) {
        assert!(lease.house_id == object::uid_to_inner(&house.id), EWrongParams);
        assert!(lease.tenant == tx_context::sender(ctx), ENoPermission);

        let deposit = table::remove<ID, Coin<SUI>>(&mut platform.deposit_pool, lease.house_id);
       
        (deposit, house)
    }


    // === Private Functions ===
    fun caculate_deduct_deposit(paid_deposit: u64, damage: u8): u64 {
        let deduct_deposit:u64 = 0;
        if (DAMAGE_LEVEL_1 == damage) {
            deduct_deposit = paid_deposit /10 * 1; 
        };
        if (DAMAGE_LEVEL_2 == damage) {
            deduct_deposit = paid_deposit / 10 * 5; 
        };
        if (DAMAGE_LEVEL_3 == damage) {
            deduct_deposit = paid_deposit; 
        };

        deduct_deposit
    }


    // === Test Functions ===
     #[test]
    fun test_rent_house() { 
        use sui::test_scenario;
        use sui::coin::mint_for_testing;
        use sui::test_utils::assert_eq;

        let admin: address = @0x11;
        let landlord: address = @0x22;
        let tenant: address = @0x33;
        let admin_id:ID;
        // let notice_id: ID;
        let house_id: ID;
        let house_monthly_rent: u64 = 2000;
        let total_fee: u64 = 3000;
        let house_area: u64 = 70;
        let house_description: vector<u8> = b"This house faces north and south, with sufficient sunlight and good ventilation. It is also close to the subway station and has a favorable price.";
        let house_photo: vector<u8> = b"https%3A%2F%2Fts1.cn.mm.bing.net%2Fth%3Fid%3DOIP-C.FNoLwTxiT7CM5e0mmMxD6AHaHT%26w%3D119%26h%3D150%26c%3D8%26rs%3D1%26qlt%3D90%26o%3D6%26pid%3D3.1%26rm%3D2";
        let damage: u8 = DAMAGE_LEVEL_1;
        let damage_description: vector<u8> = b"The house is slightly damaged";
        let damage_photo: vector<u8> = b"https%3A%2F%2Fts1.cn.mm.bing.net%2Fth%3Fid%3DOIP-C.FNoLwTxiT7CM5e0mmMxD6AHaHT%26w%3D119%26h%3D150%26c%3D8%26rs%3D1%26qlt%3D90%26o%3D6%26pid%3D3.1%26rm%3D2";

        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        // admin create a RentalPlatform share object and got Admin object
        test_scenario::next_tx(scenario, admin);
        {
            new_platform_and_transfer(test_scenario::ctx(scenario));
        };
        //landlord posts a rental notice
        test_scenario::next_tx(scenario, landlord);
        {
            let admin_object:Admin = test_scenario::take_from_address<Admin>(scenario, admin);
            admin_id = object::uid_to_inner(&admin_object.id);
            test_scenario::return_to_address<Admin>(admin, admin_object);

            let platform = test_scenario::take_shared<RentalPlatform>(scenario);
            let platform_ref = &mut platform;

            post_rental_notice_and_transfer(platform_ref, house_monthly_rent, house_area, house_description, house_photo, test_scenario::ctx(scenario));


            test_scenario::return_shared(platform);
        };
        //tenant pay rent and deposit
        test_scenario::next_tx(scenario, tenant);
        {
            let platform = test_scenario::take_shared<RentalPlatform>(scenario);
            let platform_ref = &mut platform;

            let house: House = test_scenario::take_from_address<House>(scenario, landlord);
            house_id = object::uid_to_inner(&house.id);
        
            let notice: &RentalNotice = table::borrow<ID, RentalNotice>(&platform_ref.notices, house_id);
            assert_eq(object::id_to_address(&notice.house_id), object::id_to_address(&house_id));
            assert_eq(notice.landlord, house.owner);

            let expect_deposit = notice.monthly_rent * DEPOSIT_PERCENT / 100;
            assert_eq(expect_deposit, notice.deposit);
            
            let coin = mint_for_testing(total_fee, test_scenario::ctx(scenario));
            pay_rent_and_transfer(platform_ref, object::id_to_address(&house_id),1, coin, test_scenario::ctx(scenario));

            test_scenario::return_shared(platform);
            test_scenario::return_to_address<House>(landlord, house);
        };
        // landlord transfers the house to the tenant
        test_scenario::next_tx(scenario, landlord);
        {      
            let platform = test_scenario::take_shared<RentalPlatform>(scenario);
            let platform_ref = &platform;
            let lease:Lease = test_scenario::take_immutable<Lease>(scenario);
            let house = test_scenario::take_from_address_by_id<House>(scenario, landlord, house_id);

            assert_eq(object::id_to_address(&lease.house_id), object::uid_to_address(&house.id));
            assert_eq(lease.landlord, house.owner);
            assert_eq(table::contains<ID, RentalNotice>(&platform_ref.notices, object::uid_to_inner(&house.id)), false);
            let expect_deposit = lease.paid_rent / (lease.tenancy as u64) * DEPOSIT_PERCENT / 100;
            assert_eq(expect_deposit, lease.paid_deposit); 

            transfer_house_to_tenant(&lease, house);
            landlord_inspect(&lease, damage, damage_description, damage_photo, test_scenario::ctx(scenario));

            test_scenario::return_shared(platform);
            test_scenario::return_immutable<Lease>(lease);
        };
        //The platform administrator reviews the inspection report and return a coin of deposit
        test_scenario::next_tx(scenario, admin);
        {      
            let platform = test_scenario::take_shared<RentalPlatform>(scenario);
            let platform_ref = &mut platform;

            let inspection = test_scenario::take_shared<Inspection>(scenario);
            
            let admin_object = test_scenario::take_from_address_by_id<Admin>(scenario, admin, admin_id);
            let lease = test_scenario::take_immutable<Lease>(scenario);

            review_inspection_report(platform_ref, &lease, &mut inspection, damage, &admin_object, test_scenario::ctx(scenario));

            test_scenario::return_immutable<Lease>(lease);
            test_scenario::return_to_address<Admin>(admin, admin_object);
            test_scenario::return_shared(platform);
            test_scenario::return_shared(inspection);
        };
        //The tenant returns the room to the landlord , receives the deposit
        test_scenario::next_tx(scenario, tenant);
        {      
            let platform = test_scenario::take_shared<RentalPlatform>(scenario);
            let platform_ref = &mut platform;
            let lease = test_scenario::take_immutable<Lease>(scenario);
            let house = test_scenario::take_from_address_by_id<House>(scenario, tenant, house_id);
            let inspection = test_scenario::take_shared<Inspection>(scenario);

            let expect_deduct_deposit = caculate_deduct_deposit(lease.paid_deposit, inspection.damage); 
            assert_eq(expect_deduct_deposit, inspection.deduct_deposit);


            tenant_return_house_and_transfer(platform_ref, &lease, house,test_scenario::ctx(scenario));

            test_scenario::return_immutable<Lease>(lease);
            test_scenario::return_shared(platform);
            test_scenario::return_shared(inspection);
        };
        test_scenario::end(scenario_val);
    }
}