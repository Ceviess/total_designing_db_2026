/*
Процедуры
*/

set search_path to kuzmin_food, exts;


-- Очистка тестовых данных.

create or replace procedure erase_test_data()
language sql
set search_path to kuzmin_food, exts
as $$
    delete from review;
    delete from payment;
    delete from order_structure;
    delete from courier_pay;
    delete from "order";
    delete from product;
    delete from client_address;
    delete from restaurant;
    delete from client;
    delete from courier;
    delete from product_category;
    delete from address;
$$;


-- Генератор тестовых данных

create or replace procedure insert_test_data(value int)
language plpgsql
set search_path to kuzmin_food, exts
as $$
declare
    v_client_ids uuid[];
    v_category_ids uuid[];
    v_restaurant_ids uuid[];
    v_client_address_ids uuid[];
begin
    if value is null or value <= 0 then
        raise exception 'insert_test_data: количество должно быть положительным, получено %',
            value
            using errcode = 'invalid_parameter_value';
    end if;

    delete from review;
    delete from payment;
    delete from order_structure;
    delete from courier_pay;
    delete from "order";
    delete from product;
    delete from client_address;
    delete from restaurant;
    delete from client;
    delete from courier;
    delete from product_category;
    delete from address;

    insert into client (client_id, login, password, phone_number)
    select exts.uuid_generate_v4(),
           'client_' || i,
           md5(random()::text),
           '+7900' || lpad(i::text, 7, '0')
    from generate_series(1, value) as i;

    insert into courier (courier_id, fio, phone_number, status,
                         hire_date, dismissal_date, coefficient)
    select exts.uuid_generate_v4(),
           'Курьер ' || i,
           '+7910' || lpad(i::text, 7, '0'),
           (enum_range(null::courier_status))[
               case when i % 5 = 0 then 4 else 1 end
           ],
           current_date - (30 + (i * 3) % 150),
           case
               when i % 5 = 0 then current_date - (30 + (i * 3) % 150) + 5
               else null
           end,
           0.1
    from generate_series(1, value) as i;

    insert into product_category (product_category_id, product_category_name)
    select exts.uuid_generate_v4(), 'Категория ' || i
    from generate_series(1, value) as i;

    insert into address (address_id, street, house_number, apartment_office)
    select exts.uuid_generate_v4(),
           case
               when i <= value then 'Ресторанная улица ' || i
               else 'Клиентская улица ' || (i - value)
           end,
           ((i % 50) + 1)::text,
           case when i % 10 = 0 then null else ((i % 20) + 1)::text end
    from generate_series(1, value * 5) as i;

    insert into restaurant (restaurant_id, restaurant_name, address_id,
                            description, work_start_time, work_end_time,
                            company_details, rating, status)
    select exts.uuid_generate_v4(),
           'Ресторан ' || a.rn,
           a.address_id,
           'Описание ресторана ' || a.rn,
           time '09:00' + make_interval(hours => (a.rn % 5)::int),
           time '21:00' + make_interval(hours => (a.rn % 3)::int),
           'ИНН ' || lpad(a.rn::text, 10, '0'),
           null,
           (enum_range(null::restaurant_status))[1]
    from (
        select address_id,
               row_number() over (order by street) as rn
        from address
        where street like 'Ресторанная улица %'
    ) as a;

    select array_agg(product_category_id order by product_category_name)
    into v_category_ids
    from product_category;

    select array_agg(restaurant_id order by restaurant_name)
    into v_restaurant_ids
    from restaurant;

    insert into product (product_id, product_name, product_category_id,
                         price, restaurant_id, photo_url, rating,
                         status, description)
    select exts.uuid_generate_v4(),
           'Блюдо ' || r.ord || '-' || n,
           v_category_ids[((r.ord::int + n - 2) % value) + 1],
           (100 + r.ord * 10 + n)::numeric(10, 2),
           r.restaurant_id,
           null,
           null,
           (enum_range(null::product_status))[1],
           'Описание блюда ' || r.ord || '-' || n
    from unnest(v_restaurant_ids) with ordinality as r(restaurant_id, ord)
    cross join generate_series(1, 5) as n;

    select array_agg(client_id order by login) into v_client_ids
    from client;

    select array_agg(address_id order by street) into v_client_address_ids
    from address
    where street like 'Клиентская улица %';

    insert into client_address (client_id, address_id)
    select v_client_ids[ci],
           v_client_address_ids[(ci - 1) * 4 + aj]
    from generate_series(1, value) as ci
    cross join generate_series(1, 4) as aj;
end $$;
