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
