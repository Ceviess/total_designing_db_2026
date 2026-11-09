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