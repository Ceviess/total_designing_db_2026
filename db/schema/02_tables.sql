set search_path to kuzmin_food, exts;

create table if not exists address (
    address_id uuid primary key default exts.uuid_generate_v4(),
    street varchar(200) not null,
    house_number varchar(10) not null,
    apartment_office varchar(10) null,
    constraint unique_address unique nulls not distinct (street, house_number, apartment_office)
);

create table if not exists client (
    client_id uuid primary key default exts.uuid_generate_v4(),
    login varchar(50) not null unique,
    password varchar(32) not null,
    phone_number varchar(20) not null unique
);

create table if not exists client_address (
    client_id uuid not null,
    address_id uuid not null,
    constraint pk_client_address primary key (client_id, address_id),
    constraint fk_client_address_client foreign key (client_id) references client(client_id),
    constraint fk_client_address_address foreign key (address_id) references address(address_id)
);

create table if not exists restaurant (
    restaurant_id uuid primary key default exts.uuid_generate_v4(),
    restaurant_name varchar(50) not null,
    address_id uuid not null unique,
    description text not null,
    work_start_time time not null,
    work_end_time time not null,
    company_details text not null,
    rating numeric(3,2) null,
    status restaurant_status not null,
    constraint fk_restaurant_address foreign key (address_id) references address(address_id),
    constraint check_rating check (rating between 0 and 5),
    constraint check_work_time check (work_end_time > work_start_time)
);

create table if not exists courier (
    courier_id uuid primary key default exts.uuid_generate_v4(),
    fio varchar(150) not null,
    phone_number varchar(20) not null,
    status courier_status not null,
    hire_date date not null,
    dismissal_date date null,
    coefficient numeric(3,2) not null default 0.1,
    constraint check_coefficient check (coefficient between 0.1 and 0.5),
    constraint check_dismissal_logic check ((status = 'уволен') = (dismissal_date is not null))
);

create table if not exists product_category (
    product_category_id uuid primary key default exts.uuid_generate_v4(),
    product_category_name varchar(50) not null
);

create table if not exists product (
    product_id uuid primary key default exts.uuid_generate_v4(),
    product_name varchar(50) not null,
    product_category_id uuid not null,
    price numeric(10,2) not null,
    restaurant_id uuid not null,
    photo_url text null,
    rating numeric(3,2) null,
    status product_status not null,
    description text not null,
    constraint fk_product_category foreign key (product_category_id) references product_category(product_category_id),
    constraint fk_product_restaurant foreign key (restaurant_id) references restaurant(restaurant_id),
    constraint check_product_price check (price >= 0),
    constraint check_product_rating check (rating between 0 and 5)
);

create table if not exists "order" (
    order_id uuid primary key default exts.uuid_generate_v4(),
    client_id uuid not null,
    restaurant_id uuid not null,
    courier_id uuid not null,
    address_id uuid not null,
    order_timestamp timestamp not null,
    delivery_timestamp timestamp null,
    order_amount numeric(12,2) not null,
    commission numeric(12,2) not null,
    total_amount numeric(12,2) not null,
    status order_status not null,
    pay_status order_pay_status not null,
    description text null,
    constraint fk_order_client foreign key (client_id) references client(client_id),
    constraint fk_order_restaurant foreign key (restaurant_id) references restaurant(restaurant_id),
    constraint fk_order_courier foreign key (courier_id) references courier(courier_id),
    constraint fk_order_address foreign key (address_id) references address(address_id),
    constraint fk_order_client_address foreign key (client_id, address_id) references client_address(client_id, address_id),
    constraint check_commission check (commission = round(order_amount * 0.10, 2)),
    constraint check_total_amount check (total_amount = order_amount + commission),
    constraint check_minimum_total check (total_amount >= 1000),
    constraint check_delivery_date check (delivery_timestamp is null or delivery_timestamp >= order_timestamp),
    constraint check_delivery_logic check ((status = 'доставлен') = (delivery_timestamp is not null))
);

create table if not exists order_structure (
    order_id uuid not null,
    product_id uuid not null,
    quantity numeric(10,2) not null,
    constraint pk_order_structure primary key (order_id, product_id),
    constraint fk_order_structure_order foreign key (order_id) references "order"(order_id),
    constraint fk_order_structure_product foreign key (product_id) references product(product_id),
    constraint check_order_structure_quantity check (quantity > 0)
);

create table if not exists payment (
    payment_id uuid primary key default exts.uuid_generate_v4(),
    order_id uuid not null,
    payment_type payment_type not null,
    amount numeric(12,2) not null,
    transaction_code varchar(100) not null unique,
    payment_timestamp timestamp not null,
    status payment_status not null,
    constraint fk_payment_order foreign key (order_id) references "order"(order_id)
);

create unique index if not exists unique_payment_success_per_order
    on payment (order_id)
    where status = 'успех';

create table if not exists review (
    review_id uuid primary key default exts.uuid_generate_v4(),
    client_id uuid not null,
    order_id uuid not null,
    entity_type review_entity_type not null,
    entity_id uuid not null,
    description text not null,
    photo_url text null,
    rating numeric(2,1) not null,
    review_timestamp timestamp not null,
    constraint fk_review_client foreign key (client_id) references client(client_id),
    constraint fk_review_order foreign key (order_id) references "order"(order_id),
    constraint check_review_rating check (rating between 1 and 5),
    constraint unique_review_entity unique (order_id, entity_type, entity_id)
);

create table if not exists courier_pay (
    year smallint not null,
    month smallint not null,
    courier_id uuid not null,
    amount numeric(12,2) not null,
    coefficient_used numeric(3,2) not null,
    constraint pk_courier_pay primary key (year, month, courier_id),
    constraint fk_courier_pay_courier foreign key (courier_id) references courier(courier_id),
    constraint check_courier_pay_amount check (amount >= 0),
    constraint check_courier_pay_coefficient check (coefficient_used between 0.1 and 0.5),
    constraint check_courier_pay_month check (month between 1 and 12)
);