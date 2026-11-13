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
    v_courier_ids uuid[];
    v_category_ids uuid[];
    v_restaurant_ids uuid[];
    v_client_address_ids uuid[];
    v_all_product_ids uuid[];
    v_all_prices numeric[];
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
    v_order_amount numeric(12,2);
    v_commission numeric(12,2);
    v_total numeric(12,2);
    v_product_ids uuid[];
    v_prices numeric[];
    v_quantities numeric[];
    v_product_count int;
    v_client_index int;
    v_restaurant_index int;
    v_i int;
    v_j int;
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

    select array_agg(courier_id order by fio) into v_courier_ids
    from courier;

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

    select array_agg(p.product_id order by r.restaurant_name, p.product_name),
           array_agg(p.price order by r.restaurant_name, p.product_name)
    into v_all_product_ids, v_all_prices
    from product p
    join restaurant r on r.restaurant_id = p.restaurant_id;

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

    -- Заказы, позиции, оплаты и отзывы.

    v_delivered_order_ids := array[]::uuid[];
    v_delivered_client_ids := array[]::uuid[];
    v_delivered_restaurant_ids := array[]::uuid[];
    v_delivered_product_ids := array[]::uuid[];
    v_delivered_times := array[]::timestamp[];

    for v_i in 1..value * 5 loop
        v_client_index := ((v_i - 1) % value) + 1;
        v_client_id := v_client_ids[v_client_index];
        v_address_id := v_client_address_ids[
            (v_client_index - 1) * 4 + (1 + (v_i * 3) % 4)
        ];
        v_restaurant_index := ((v_i - 1) % value) + 1;
        v_restaurant_id := v_restaurant_ids[v_restaurant_index];
        v_courier_id := v_courier_ids[((v_i * 3) % value) + 1];

        v_order_time := localtimestamp
            - make_interval(days => (v_i * 13) % 150,
                            hours => 1 + (v_i * 7) % 23);

        if v_i % 5 = 0 then
            v_status := case
                when v_i % 20 = 0 then 'отменён'
                when v_i % 10 = 0 then 'в_доставке'
                else 'готовится'
            end;
        else
            v_status := 'доставлен';
        end if;

        if v_status = 'доставлен' then
            v_delivery_time := v_order_time
                + make_interval(mins => 10 + (v_i * 5) % 40);
        else
            v_delivery_time := null;
        end if;

        v_product_count := 1 + (v_i % 5);
        v_product_ids := v_all_product_ids[
            (v_restaurant_index - 1) * 5 + 1
            : (v_restaurant_index - 1) * 5 + v_product_count
        ];
        v_prices := v_all_prices[
            (v_restaurant_index - 1) * 5 + 1
            : (v_restaurant_index - 1) * 5 + v_product_count
        ];

        v_quantities := array[]::numeric[];
        v_order_amount := 0;

        for v_j in 1..v_product_count loop
            v_quantities := v_quantities || (1 + ((v_i + v_j) % 3))::numeric;
            v_order_amount := v_order_amount + v_prices[v_j] * v_quantities[v_j];
        end loop;

        if v_order_amount < 1000 then
            v_quantities[1] := v_quantities[1]
                + ceil((1000 - v_order_amount) / v_prices[1]);

            v_order_amount := 0;

            for v_j in 1..v_product_count loop
                v_order_amount := v_order_amount
                    + v_prices[v_j] * v_quantities[v_j];
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
                v_status, 'оплачен', 'Заказ ' || v_i);

        for v_j in 1..v_product_count loop
            insert into order_structure (order_id, product_id, quantity)
            values (v_order_id, v_product_ids[v_j], v_quantities[v_j]);
        end loop;

        insert into payment (payment_id, order_id, payment_type, amount,
                             transaction_code, payment_timestamp, status)
        values (exts.uuid_generate_v4(), v_order_id,
                (enum_range(null::payment_type))[1 + (v_i % 3)],
                v_total, 'tx-' || lpad(v_i::text, 10, '0'),
                v_order_time + make_interval(mins => 5), 'успех');

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
                v_delivered_product_ids, v_product_ids[1]
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
                v_delivered_order_ids[v_j], 'ресторан',
                v_delivered_restaurant_ids[v_j],
                'Отзыв о ресторане ' || v_j, null,
                (1 + (v_j % 5))::numeric(2,1),
                v_delivered_times[v_j] + make_interval(mins => 10));
    end loop;

    for v_j in 1..value loop
        insert into review (review_id, client_id, order_id, entity_type,
                            entity_id, description, photo_url, rating,
                            review_timestamp)
        values (exts.uuid_generate_v4(), v_delivered_client_ids[v_j],
                v_delivered_order_ids[v_j], 'блюдо',
                v_delivered_product_ids[v_j],
                'Отзыв о блюде ' || v_j, null,
                (1 + (v_j % 5))::numeric(2,1),
                v_delivered_times[v_j] + make_interval(mins => 10));
    end loop;

    -- Выплаты курьерам.

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
    group by months.month_start, c.courier_id, c.coefficient;
end $$;


-- Добавление блюда

create or replace procedure add_product(
    p_restaurant_id uuid,
    p_product_category_id uuid,
    p_name varchar(50),
    p_price numeric(10,2),
    p_status product_status,
    p_description text,
    p_rating numeric(3,2) default null,
    p_photo_url text default null
)
language plpgsql
set search_path to kuzmin_food, exts
as $$
begin
    if not exists (select 1 from restaurant
                   where restaurant_id = p_restaurant_id) then
        raise exception 'add_product: ресторан с идентификатором % не найден',
            p_restaurant_id
            using errcode = 'no_data_found';
    end if;

    if not exists (select 1 from product_category
                   where product_category_id = p_product_category_id) then
        raise exception 'add_product: категория с идентификатором % не найдена',
            p_product_category_id
            using errcode = 'no_data_found';
    end if;

    if p_price < 0 then
        raise exception 'add_product: цена блюда не может быть отрицательной: %',
            p_price
            using errcode = 'invalid_parameter_value';
    end if;

    if p_rating is not null and (p_rating < 0 or p_rating > 5) then
        raise exception 'add_product: рейтинг блюда должен быть от 0 до 5: %',
            p_rating
            using errcode = 'invalid_parameter_value';
    end if;

    insert into product (product_id, product_name, product_category_id,
                         price, restaurant_id, photo_url, rating,
                         status, description)
    values (exts.uuid_generate_v4(), p_name, p_product_category_id,
            p_price, p_restaurant_id, p_photo_url, p_rating,
            p_status, p_description);
end $$;


-- Расчёт зарплаты курьеров

create or replace procedure courier_salary()
language plpgsql
set search_path to kuzmin_food, exts
as $$
declare
    v_year smallint;
    v_month smallint;
    v_courier record;
    v_order_count int;
    v_commission numeric(12,2);
    v_coefficient numeric(3,2);
    v_new_coefficient numeric(3,2);
    v_amount numeric(12,2);
begin
    v_year := extract(year from localtimestamp)::smallint;
    v_month := extract(month from localtimestamp)::smallint;

    for v_courier in
        select courier_id, status, coefficient
        from courier
    loop
        select count(*), coalesce(sum(commission), 0)
        into v_order_count, v_commission
        from "order"
        where courier_id = v_courier.courier_id
          and status = 'доставлен'
          and extract(year from order_timestamp) = v_year
          and extract(month from order_timestamp) = v_month;

        select coefficient_used
        into v_coefficient
        from courier_pay
        where year = v_year
          and month = v_month
          and courier_id = v_courier.courier_id;

        if not found then
            v_coefficient := v_courier.coefficient;
        end if;

        if v_order_count <= 150 then
            v_new_coefficient := 0.1;
        elsif v_order_count <= 250 then
            v_new_coefficient := 0.2;
        elsif v_order_count <= 500 then
            v_new_coefficient := 0.3;
        else
            v_new_coefficient := 0.5;
        end if;

        v_amount := round(v_commission * v_coefficient, 2);

        insert into courier_pay (year, month, courier_id, amount,
                                 coefficient_used)
        values (v_year, v_month, v_courier.courier_id, v_amount,
                v_coefficient)
        on conflict (year, month, courier_id) do update
        set amount = excluded.amount,
            coefficient_used = excluded.coefficient_used;

        if v_courier.status <> 'уволен' then
            update courier
            set coefficient = v_new_coefficient
            where courier_id = v_courier.courier_id;
        end if;
    end loop;
end $$;
