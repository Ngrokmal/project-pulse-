\set ON_ERROR_STOP on
insert into auth.users(id,email,raw_user_meta_data) values
 ('11111111-1111-4111-8111-111111111111','journal-a@example.invalid','{}'),
 ('22222222-2222-4222-8222-222222222222','journal-b@example.invalid','{}'),
 ('33333333-3333-4333-8333-333333333333','journal-outside@example.invalid','{}');
insert into public.conversations(id,kind,title,created_by) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','group','Journal test','11111111-1111-4111-8111-111111111111');
insert into public.conversation_members(conversation_id,user_id,role) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','owner'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','22222222-2222-4222-8222-222222222222','member');
insert into public.messages(id,conversation_id,sender_id,body,client_id) values
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','existing synthetic message','journal-preexisting');
