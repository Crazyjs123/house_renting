module house_renting::house_renting {
    // === Imports ===
    use std::string::{Self, String};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::table::{Table, Self};


    // === Constants ===
    // Damage levels
    const DAMAGE_LEVEL_UNKNOWN: u8 = 0;
    const DAMAGE_LEVEL_0: u8 = 1;
    const DAMAGE_LEVEL_1: u8 = 2;
    const DAMAGE_LEVEL_2: u8 = 3;
    const DAMAGE_LEVEL_3: u8 = 4;

    // Review status
    const WAITING_FOR_REVIEW: u8 = 0;
    const REVIEWED: u8 = 1;

    // Deposit percent to monthly rent
    const DEPOSIT_PERCENT: u64 = 50;

    // Error codes
    const ETenancyIncorrect: u64 = 1;
    const EInvalidSuiAmount: u64 = 2;
    const EDamageIncorrect: u64 = 3;
    const ENoPermission: u64 = 4;
    const EWrongParams: u64 = 5;
    const EInspectionReviewed: u64 = 6;
    const EInvalidNotice: u64 = 7;


    // === Structs ===
    // Rental platform for landlords and tenants
    struct RentalPlatform has key, store {
        id: UID,
        deposit_pool: Table<ID, Coin<SUI>>,
        notices: Table<ID, RentalNotice>,
        owner: address,
    }

    // Rental platform administrator
    struct Admin has key, store {
        id: UID,
    }

    // Rental notice issued by the landlord
    struct RentalNotice has key, store {
        id: UID,
        monthly_rent: u64,
        deposit: u64,
        house_id: ID,
        landlord: address,
    }

    // House details
    struct House has key {
        id: UID,
        area: u64,
        owner: address,
        photo: String,
        description: String,
    }

    // Lease contract between tenant and landlord
    struct Lease has key, store {
        id: UID,
        house_id: ID,
        tenant: address,
        landlord: address,
        tenancy: u32,
        paid_rent: u64,
        paid_deposit: u64,
    }

    // Inspection report submitted by landlord
    struct Inspection has key, store {
        id: UID,
        house_id: ID,
        lease_id: ID,
        damage: u8,
        damage_description: String,
        damage_photo: String,
        damage_assessment_ret: u8,
        deduct_deposit: u64,
        review_status: u8,
    }


    // === Public-Mutative Functions ===
    // Create a new rental platform and transfer admin object
    public entry fun new_platform_and_transfer(ctx: &mut TxContext) {
        let admin = new_platform(ctx);
        transfer::public_transfer(admin, tx_context::sender(ctx))
    }

    // Landlord posts a rental notice and transfers the associated house
    public entry fun post_rental_notice_and_transfer(
        platform: &mut RentalPlatform,
        monthly_rent: u64,
        housing_area: u64,
        description: vector<u8>,
        photo: vector<u8>,
        ctx: &mut TxContext,
    ) {
        let house = post_rental_notice(platform, monthly_rent, housing_area, description, photo, ctx);
        transfer::transfer(house, tx_context::sender(ctx));
    }

    // Tenant pays rent and transfers the coin to the landlord
    public entry fun pay_rent_and_transfer(
        platform: &mut RentalPlatform,
        house_address: address,
        tenancy: u32,
        paid: Coin<SUI>,
        ctx: &mut TxContext,
    ) {
        let house_id: ID = object::id_from_address(house_address);
        let (paid, landlord) = pay_rent(platform, house_id, tenancy, paid, ctx);
        transfer::public_transfer(paid, landlord);
    }

    // Tenant returns the house to the landlord and receives the deposit
    public entry fun tenant_return_house_and_transfer(
        platform: &mut RentalPlatform,
        lease: &Lease,
        house: House,
        ctx: &mut TxContext,
    ) {
        let (deposit, house) = tenant_return_house(platform, lease, house, ctx);
        if coin::value(&deposit) > 0 {
            transfer::public_transfer(deposit, tx_context::sender(ctx));
        } else {
            coin::destroy_zero<SUI>(deposit);
        };
        transfer::transfer(house, lease.landlord)
    }

    // Landlord inspects the house and submits an inspection report
    public entry fun landlord_inspect(
        lease: &Lease,
        damage: u8,
        damage_description: vector<u8>,
        damage_photo: vector<u8>,
        ctx: &mut TxContext,
    ) {
        assert!(lease.landlord == tx_context::sender(ctx), ENoPermission);
        assert!(damage >= DAMAGE_LEVEL_0 && damage <= DAMAGE_LEVEL_3, EDamageIncorrect);
        let inspection = Inspection {
            id: object::new(ctx),
            house_id: lease.house_id,
            lease_id: object::uid_to_inner(&lease.id),
            damage: damage,
            damage_description: string::utf8(damage_description),
            damage_photo: string::utf8(damage_photo),
            damage_assessment_ret: DAMAGE_LEVEL_UNKNOWN,
            deduct_deposit: 0,
            review_status: WAITING_FOR_REVIEW,
        };

        transfer::public_share_object(inspection);
    }

    // Administrator reviews the inspection report and returns a portion of the deposit
    public entry fun review_inspection_report(
        platform: &mut RentalPlatform,
        lease: &Lease,
        inspection: &mut Inspection,
        damage: u8,
        _: &Admin,
        ctx: &mut TxContext,
    ) {
        assert!(lease.house_id == inspection.house_id, EWrongParams);
        assert!(inspection.review_status == WAITING_FOR_REVIEW, EInspectionReviewed);
        assert!(damage >= DAMAGE_LEVEL_0 && damage <= DAMAGE_LEVEL_3, EDamageIncorrect);

        let deduct_deposit: u64 = calculate_deduct_deposit(lease.paid_deposit, damage);

        inspection.damage_assessment_ret = damage;
        inspection.review_status = REVIEWED;
        inspection.deduct_deposit = deduct_deposit;

        if deduct_deposit > 0 {
            let coin = coin::split(
                table::borrow_mut<ID, Coin<SUI>>(&mut platform.deposit_pool, lease.house_id),
                deduct_deposit,
                ctx,
            );
            transfer::public_transfer(coin, lease.landlord);
        }
    }


    // === Private Functions ===
    // Create a new rental platform object and initialize its fields
    private fun new_platform(ctx: &mut TxContext) -> Admin {
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

    // Landlord posts a rental notice, creates a house object, and returns the house
    private fun post_rental_notice(
        platform: &mut RentalPlatform,
        monthly_rent: u64,
        housing_area: u64,
        description: vector<u8>,
        photo: vector<u8>,
        ctx: &mut TxContext,
    ) -> House {
        let deposit = (monthly_rent * DEPOSIT_PERCENT) / 100;

        let house = House {
            id: object::new(ctx),
            area: housing_area,
            owner: tx_context::sender(ctx),
            photo: string::utf8(photo),
            description: string::utf8(description),
        };
        let rentalnotice = RentalNotice {
            id: object::new(ctx),
            deposit: deposit,
            monthly_rent: monthly_rent,
            house_id: object::uid_to_inner(&house.id),
            landlord: tx_context::sender(ctx),
        };

        table::add<ID, RentalNotice>(&mut platform.notices, object::uid_to_inner(&house.id), rentalnotice);

        house
    }

    // Tenant pays rent and signs rental contract
    private fun pay_rent(
        platform: &mut RentalPlatform,
        house_id: ID,
        tenancy: u32,
        paid: Coin<SUI>,
        ctx: &mut TxContext,
    ) -> (Coin<SUI>, address) {
        assert!(tenancy > 0, ETenancyIncorrect);
        assert!(table::contains<ID, RentalNotice>(&platform.notices, house_id), EInvalidNotice);

        let notice = table::borrow<ID, RentalNotice>(&platform.notices, house_id);
        let rent = notice.monthly_rent * (tenancy as u64);
        let total_fee = rent + notice.deposit;
        assert!(total_fee == coin::value(&paid), EInvalidSuiAmount);

        let deposit_coin = coin::split<SUI>(&mut paid, notice.deposit, ctx);
        if table::contains<ID, Coin<SUI>>(&platform.deposit_pool, notice.house_id) {
            coin::join(
                table::borrow_mut<ID, Coin<SUI>>(&mut platform.deposit_pool, notice.house_id),
                deposit_coin
            )
        } else {
            table::add(&mut platform.deposit_pool, notice.house_id, deposit_coin)
        };

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

        let RentalNotice { id: notice_id, monthly_rent: _, deposit: _, house_id: _, landlord: landlord } = table::remove<ID, RentalNotice>(&mut platform.notices, house_id);
        object::delete(notice_id);

        (paid, landlord)
    }

    // Tenant returns the house to the landlord and receives the deposit
    private fun tenant_return_house(
        platform: &mut RentalPlatform,
        lease: &Lease,
        house: House,
        ctx: &mut TxContext,
    ) -> (Coin<SUI>, House) {
        assert!(lease.house_id == object::uid_to_inner(&house.id), EWrongParams);
        assert!(lease.tenant == tx_context::sender(ctx), ENoPermission);

        let deposit = table::remove<ID, Coin<SUI>>(&mut platform.deposit_pool, lease.house_id);

        (deposit, house)
    }

    // Calculate the amount of deposit to deduct based on the damage level
    private fun calculate_deduct_deposit(paid_deposit: u64, damage: u8) -> u64 {
        let mut deduct_deposit: u64 = 0;
        if DAMAGE_LEVEL_1 == damage {
            deduct_deposit = paid_deposit / 10 * 1;
        };
        if DAMAGE_LEVEL_2 == damage {
            deduct_deposit = paid_deposit / 10 * 5;
        };
        if DAMAGE_LEVEL_3 == damage {
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

            let expect_deduct_deposit = calculate_deduct_deposit(lease.paid_deposit, inspection.damage); 
            assert_eq(expect_deduct_deposit, inspection.deduct_deposit);


            tenant_return_house_and_transfer(platform_ref, &lease, house,test_scenario::ctx(scenario));

            test_scenario::return_immutable<Lease>(lease);
            test_scenario::return_shared(platform);
            test_scenario::return_shared(inspection);
        };
        test_scenario::end(scenario_val);
    }
}