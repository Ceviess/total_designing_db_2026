/*
Процедуры
*/

set search_path to kuzmin_food, exts;

drop procedure if exists erase_test_data();

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

drop procedure if exists insert_test_data(integer);

create or replace procedure insert_test_data(value int)
language plpgsql
set search_path to kuzmin_food, exts
as $$
declare
    v_alphabet text := 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя';
    v_client_ids uuid[];
    v_courier_ids uuid[];
    v_active_courier_ids uuid[];
    v_category_ids uuid[];
    v_restaurant_ids uuid[];
    v_address_ids uuid[];
    v_product_ids uuid[];
    v_prices numeric[];
    v_delivered_order_ids uuid[];
    v_delivered_client_ids uuid[];
    v_delivered_restaurant_ids uuid[];
    v_delivered_product_ids uuid[];
    v_delivered_times timestamp[];
    v_order_id uuid;
    v_client_id uuid;
    v_restaurant_id uuid;
    v_courier_id uuid;
    v_address_id uuid;
    v_order_time timestamp;
    v_delivery_time timestamp;
    v_status order_status;
    v_pay_status order_pay_status;
    v_order_amount numeric(10,2);
    v_commission numeric(10,2);
    v_total numeric(10,2);
    v_product_ids_in_order uuid[];
    v_prices_in_order numeric[];
    v_quantities numeric[];
    v_product_count int;
    v_client_index int;
    v_restaurant_index int;
    v_client_offset int;
    v_address_offset int;
    v_i int;
    v_j int;
begin
    if value is null or value <= 0 then
        raise exception 'insert_test_data: количество должно быть положительным, получено %',
            value
            using errcode = 'invalid_parameter_value';
    end if;
    select count(*) into v_client_offset from client;
    select count(*) into v_address_offset from address;
    select array_agg(exts.uuid_generate_v4() order by g)
    into v_client_ids
    from generate_series(1, value) as g;
    insert into client (client_id, login, password, phone_number)
    select v_client_ids[g],
           md5(random()::text),
           md5(random()::text),
           '+7' || lpad((v_client_offset + g)::text, 10, '0')
    from generate_series(1, value) as g;
    select array_agg(exts.uuid_generate_v4() order by g)
    into v_courier_ids
    from generate_series(1, value) as g;
    insert into courier (courier_id, last_name, first_name, middle_name,
                         phone_number, status, hire_date, dismissal_date,
                         coefficient)
    select v_courier_ids[g],
           substring(v_alphabet, 1, 1 + (random() * 32)::int),
           substring(v_alphabet, 1, 1 + (random() * 32)::int),
           substring(v_alphabet, 1, 1 + (random() * 32)::int),
           '+7' || lpad(g::text, 10, '0'),
           case
               when g % 5 = 0 then (enum_range(null::courier_status))[4]
               else (enum_range(null::courier_status))[1 + ((g - 1) % 3)]
           end,
           current_date - (30 + (g * 3) % 150),
           case
               when g % 5 = 0
                   then current_date - (30 + (g * 3) % 150) + 5
           end,
           0.1
    from generate_series(1, value) as g;
    select array_agg(courier_id order by courier_id)
    into v_active_courier_ids
    from courier
    where courier_id = any(v_courier_ids)
      and status <> 'уволен';
    select array_agg(exts.uuid_generate_v4() order by g)
    into v_category_ids
    from generate_series(1, value) as g;
    insert into product_category (product_category_id, product_category_name)
    select v_category_ids[g],
           substring(v_alphabet, 1, 1 + (random() * 32)::int)
    from generate_series(1, value) as g;
    select array_agg(exts.uuid_generate_v4() order by g)
    into v_address_ids
    from generate_series(1, value * 5) as g;
    insert into address (address_id, street, house_number, apartment_office)
    select v_address_ids[g],
           repeat(substring(v_alphabet, 1, 1 + (random() * 32)::int),
                  1 + (random() * 5)::int),
           (v_address_offset + g)::text,
           case when g % 10 = 0 then null else ((g % 20) + 1)::text end
    from generate_series(1, value * 5) as g;
    select array_agg(exts.uuid_generate_v4() order by g)
    into v_restaurant_ids
    from generate_series(1, value) as g;
    insert into restaurant (restaurant_id, restaurant_name, address_id,
                            description, work_start, work_end,
                            inn, ogrn, bank_account, rating, status)
    select v_restaurant_ids[g],
           substring(v_alphabet, 1, 1 + (random() * 32)::int),
           v_address_ids[g],
           md5(random()::text),
           time '09:00' + make_interval(hours => (g % 5)::int),
           time '21:00' + make_interval(hours => (g % 3)::int),
           '77' || lpad(g::text, 8, '0'),
           '1' || lpad(g::text, 12, '0'),
           '40817810' || lpad(g::text, 12, '0'),
           null,
           case
               when g % 5 = 0 then (enum_range(null::restaurant_status))[2]
               else (enum_range(null::restaurant_status))[1]
           end
    from generate_series(1, value) as g;
    select array_agg(exts.uuid_generate_v4() order by g),
           array_agg(
               (100 + ((g - 1) / 5) * 10 + ((g - 1) % 5 + 1))::numeric(8,2)
               order by g
           )
    into v_product_ids, v_prices
    from generate_series(1, value * 5) as g;
    insert into product (product_id, product_name, product_category_id,
                         price, restaurant_id, photo_url, rating,
                         status, description)
    select v_product_ids[g],
           substring(v_alphabet, 1, 1 + (random() * 32)::int),
           v_category_ids[((g - 1) % value) + 1],
           v_prices[g],
           v_restaurant_ids[((g - 1) / 5) + 1],
           null,
           null,
           (enum_range(null::product_status))[1 + ((g - 1) % 3)],
           md5(random()::text)
    from generate_series(1, value * 5) as g;
    insert into client_address (client_id, address_id)
    select v_client_ids[ci],
           v_address_ids[value + (ci - 1) * 4 + aj]
    from generate_series(1, value) as ci
    cross join generate_series(1, 4) as aj;
    v_delivered_order_ids := array[]::uuid[];
    v_delivered_client_ids := array[]::uuid[];
    v_delivered_restaurant_ids := array[]::uuid[];
    v_delivered_product_ids := array[]::uuid[];
    v_delivered_times := array[]::timestamp[];
    for v_i in 1..value * 5 loop
        v_client_index := ((v_i - 1) % value) + 1;
        v_client_id := v_client_ids[v_client_index];
        v_address_id := v_address_ids[
            value + (v_client_index - 1) * 4 + (1 + (v_i * 3) % 4)
        ];
        v_restaurant_index := ((v_i - 1) % value) + 1;
        v_restaurant_id := v_restaurant_ids[v_restaurant_index];
        v_courier_id := v_active_courier_ids[
            ((v_i - 1) % array_length(v_active_courier_ids, 1)) + 1
        ];
        v_order_time := localtimestamp
            - make_interval(days => (v_i * 13) % 150,
                            hours => 1 + (v_i * 7) % 23);
        if v_i % 5 = 0 then
            v_status := (enum_range(null::order_status))[
                case
                    when (v_i / 5) % 4 = 0 then 5
                    else (v_i / 5) % 4
                end
            ];
        else
            v_status := (enum_range(null::order_status))[4];
        end if;
        if v_status = 'доставлен' then
            v_delivery_time := v_order_time
                + make_interval(mins => 10 + (v_i * 5) % 40);
            v_pay_status := (enum_range(null::order_pay_status))[2];
        elsif v_status = 'отменён' then
            v_delivery_time := null;
            v_pay_status := (enum_range(null::order_pay_status))[3];
        else
            v_delivery_time := null;
            v_pay_status := (enum_range(null::order_pay_status))[1];
        end if;
        v_product_count := 1 + (v_i % 5);
        v_product_ids_in_order := v_product_ids[
            (v_restaurant_index - 1) * 5 + 1
            : (v_restaurant_index - 1) * 5 + v_product_count
        ];
        v_prices_in_order := v_prices[
            (v_restaurant_index - 1) * 5 + 1
            : (v_restaurant_index - 1) * 5 + v_product_count
        ];
        v_quantities := array[]::numeric[];
        v_order_amount := 0;
        for v_j in 1..v_product_count loop
            v_quantities := v_quantities || (1 + ((v_i + v_j) % 3))::numeric;
            v_order_amount := v_order_amount
                + v_prices_in_order[v_j] * v_quantities[v_j];
        end loop;
        if v_order_amount < 1000 then
            v_quantities[1] := v_quantities[1]
                + ceil((1000 - v_order_amount) / v_prices_in_order[1]);
            v_order_amount := 0;
            for v_j in 1..v_product_count loop
                v_order_amount := v_order_amount
                    + v_prices_in_order[v_j] * v_quantities[v_j];
            end loop;
        end if;
        v_order_amount := round(v_order_amount, 2);
        v_commission := round(v_order_amount * 0.10, 2);
        v_total := v_order_amount + v_commission;
        v_order_id := exts.uuid_generate_v4();
        insert into "order" (order_id, client_id, restaurant_id, courier_id,
                             address_id, order_timestamp, delivery_timestamp,
                             order_amount, commission, total_amount,
                             status, pay_status, description)
        values (v_order_id, v_client_id, v_restaurant_id, v_courier_id,
                v_address_id, v_order_time, v_delivery_time,
                v_order_amount, v_commission, v_total,
                v_status, v_pay_status, null);
        for v_j in 1..v_product_count loop
            insert into order_structure (order_id, product_id, quantity)
            values (v_order_id, v_product_ids_in_order[v_j],
                    v_quantities[v_j]);
        end loop;
        insert into payment (payment_id, order_id, payment_type, amount,
                             transaction_code, payment_timestamp, status)
        values (exts.uuid_generate_v4(), v_order_id,
                (enum_range(null::payment_type))[1 + (v_i % 3)],
                v_total, md5(random()::text),
                v_order_time + make_interval(mins => 5),
                case
                    when v_status = 'доставлен'
                        then (enum_range(null::payment_status))[1]
                    when v_status = 'отменён'
                        then (enum_range(null::payment_status))[2]
                    else (enum_range(null::payment_status))[3]
                end);
        if v_status = 'доставлен' then
            v_delivered_order_ids := array_append(
                v_delivered_order_ids, v_order_id
            );
            v_delivered_client_ids := array_append(
                v_delivered_client_ids, v_client_id
            );
            v_delivered_restaurant_ids := array_append(
                v_delivered_restaurant_ids, v_restaurant_id
            );
            v_delivered_product_ids := array_append(
                v_delivered_product_ids, v_product_ids_in_order[1]
            );
            v_delivered_times := array_append(
                v_delivered_times, v_delivery_time
            );
        end if;
    end loop;
    for v_j in 1..array_length(v_delivered_order_ids, 1) loop
        insert into review (review_id, client_id, order_id, entity_type,
                            entity_id, description, photo_url, rating,
                            review_timestamp)
        values (exts.uuid_generate_v4(), v_delivered_client_ids[v_j],
                v_delivered_order_ids[v_j],
                (enum_range(null::review_entity_type))[2],
                v_delivered_restaurant_ids[v_j],
                md5(random()::text), null,
                (1 + (v_j % 5))::numeric(2,1),
                v_delivered_times[v_j] + make_interval(mins => 10));
    end loop;
    for v_j in 1..value loop
        insert into review (review_id, client_id, order_id, entity_type,
                            entity_id, description, photo_url, rating,
                            review_timestamp)
        values (exts.uuid_generate_v4(), v_delivered_client_ids[v_j],
                v_delivered_order_ids[v_j],
                (enum_range(null::review_entity_type))[
                    case when v_j % 2 = 0 then 1 else 3 end
                ],
                case
                    when v_j % 2 = 0 then v_delivered_product_ids[v_j]
                    else v_delivered_order_ids[v_j]
                end,
                md5(random()::text), null,
                (1 + (v_j % 5))::numeric(2,1),
                v_delivered_times[v_j] + make_interval(mins => 10));
    end loop;
    insert into courier_pay (year, month, courier_id, amount,
                             coefficient_used)
    select extract(year from months.month_start)::smallint,
           extract(month from months.month_start)::smallint,
           c.courier_id,
           round(coalesce(sum(o.commission), 0) * c.coefficient, 2),
           c.coefficient
    from courier c
    cross join (
        select date_trunc('month', localtimestamp)
               - make_interval(months => n) as month_start
        from generate_series(0, 5) as n
    ) as months
    left join "order" o
           on o.courier_id = c.courier_id
          and o.status = 'доставлен'
          and o.order_timestamp >= months.month_start
          and o.order_timestamp < months.month_start + interval '1 month'
    where c.courier_id = any(v_courier_ids)
    group by months.month_start, c.courier_id, c.coefficient;
end $$;
drop procedure if exists add_product(uuid, uuid, varchar, numeric,
                                     product_status, text, numeric, text);
create or replace procedure add_product(
    p_restaurant_id uuid,
    p_product_category_id uuid,
    p_name varchar(50),
    p_price numeric,
    p_status product_status,
    p_description text,
    p_rating numeric default null,
    p_photo_url text default null
)
language sql
set search_path to kuzmin_food, exts
as $$
    insert into product (product_name, product_category_id, price,
                         restaurant_id, photo_url, rating, status,
                         description)
    values (p_name, p_product_category_id, p_price, p_restaurant_id,
            p_photo_url, p_rating, p_status, p_description);
$$;
drop procedure if exists courier_salary();
create or replace procedure courier_salary()
language sql
set search_path to kuzmin_food, exts
as $$
    with stats as (
        select o.courier_id,
               count(*) as order_count,
               sum(o.commission) as commission
        from "order" o
        where o.status = 'доставлен'
          and o.order_timestamp >= date_trunc('month', localtimestamp)
          and o.order_timestamp < date_trunc('month', localtimestamp)
                                    + interval '1 month'
        group by o.courier_id
    ),
    payout as (
        insert into courier_pay (year, month, courier_id, amount,
                                 coefficient_used)
        select extract(year from localtimestamp)::smallint,
               extract(month from localtimestamp)::smallint,
               c.courier_id,
               round(coalesce(s.commission, 0)
                     * coalesce(cp.coefficient_used, c.coefficient), 2),
               coalesce(cp.coefficient_used, c.coefficient)
        from courier c
        left join stats s on s.courier_id = c.courier_id
        left join courier_pay cp
               on cp.courier_id = c.courier_id
              and cp.year = extract(year from localtimestamp)::smallint
              and cp.month = extract(month from localtimestamp)::smallint
        on conflict (year, month, courier_id) do update
        set amount = excluded.amount,
            coefficient_used = excluded.coefficient_used
    )
    update courier c
    set coefficient = coalesce((
            select case
                    when s.order_count <= 150 then 0.1
                    when s.order_count <= 250 then 0.2
                    when s.order_count <= 500 then 0.3
                    else 0.5
                end
            from stats s
            where s.courier_id = c.courier_id
        ), 0.1)
    where c.status <> 'уволен';
$$;
