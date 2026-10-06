// Runs the AutoWave migration in an in-process Postgres (PGlite) with a
// minimal stand-in for Supabase's auth schema, then exercises the full flow:
// roles -> search -> request -> accept -> escrow -> complete -> release -> review,
// plus RLS isolation, cancellation refunds, recycling and withdrawals.
//   cd supabase/tests && npm i @electric-sql/pglite && node db_test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const sql = readFileSync(path.join(here, '../migrations/20261003000000_autowave.sql'), 'utf8');
const db = new PGlite();

let passed = 0;
const ok = (cond, msg) => { if (!cond) throw new Error('FAIL: ' + msg); passed++; console.log('  ✓ ' + msg); };
const fails = async (fn, re, msg) => {
  try { await fn(); } catch (e) { ok(re.test(e.message), `${msg} (${e.message})`); return; }
  throw new Error('FAIL (no error): ' + msg);
};

await db.exec(`
  create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
  create schema auth;
  create table auth.users (id uuid primary key, phone text, raw_user_meta_data jsonb default '{}');
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.uid', true), '')::uuid $$;
  create publication supabase_realtime;
  grant usage on schema public, auth to anon, authenticated;
`);
await db.exec(sql);
await db.exec(`
  grant select on all tables in schema public to authenticated;
  grant insert, update, delete on public.reviews, public.mechanic_locations, public.learn_messages to authenticated;
  grant execute on all functions in schema public to authenticated;
  revoke execute on function public._wallet_apply(uuid,bigint,text,uuid,text,text), public._escrow_refund(uuid,text),
    public._escrow_release(uuid,text), public.credit_topup(text,bigint,jsonb), public.pay_recycling(uuid,bigint),
    public.auto_release_escrow(), public.fail_withdrawal(uuid,text) from authenticated;
`);
console.log('migration applied');

const D = '11111111-1111-1111-1111-111111111111';   // driver
const M = '22222222-2222-2222-2222-222222222222';   // mechanic near Yaba
const M2 = '33333333-3333-3333-3333-333333333333';  // mechanic far away (Abuja)
const X = '44444444-4444-4444-4444-444444444444';   // another driver

await db.exec(`insert into auth.users (id, phone, raw_user_meta_data) values
  ('${D}', '+2348010000001', '{"full_name":"Ada Obi"}'), ('${M}', '+2348020000002', '{"full_name":"Tunde"}'),
  ('${M2}', null, '{}'), ('${X}', null, '{"full_name":"Bisi"}')`);

async function as(uid, q, params = []) {
  await db.exec(`reset role; select set_config('request.jwt.uid', '${uid ?? ''}', false); set role authenticated;`);
  try { return (await db.query(q, params)).rows; } finally { await db.exec('reset role'); }
}
async function admin(q, params = []) { await db.exec('reset role'); return (await db.query(q, params)).rows; }

console.log('phase 1: profiles and roles');
ok((await admin(`select count(*)::int n from profiles`))[0].n === 4, 'profile + wallet created on sign-up');
await as(D, `select set_my_role('driver', 'Ada Obi', '+2348010000001', 'NG')`);
await as(M, `select set_my_role('mechanic', 'Tunde Bakare', '+2348020000002', 'NG')`);
await as(M2, `select set_my_role('mechanic')`);
await as(X, `select set_my_role('driver')`);
await fails(() => as(D, `select set_my_role('mechanic')`), /already set up as a driver/, 'role cannot be switched');
ok((await as(D, `select * from profiles`)).length === 1, 'driver sees only own profile');

console.log('phase 2: mechanics and search');
await fails(() => as(D, `select save_mechanic_profile('X','',array['Battery'],1,'a',6.5,3.3,10,1)`), /Only mechanics/, 'drivers cannot create workshops');
await as(M, `select save_mechanic_profile('Tunde Auto Works','Engines and electrics',array['Engine repair','Battery & electrics'],1500000,'Yaba, Lagos',6.5095,3.3711,20,8)`);
await as(M2, `select save_mechanic_profile('Capital Motors','',array['Engine repair'],500000,'Wuse, Abuja',9.0765,7.3986,20,3)`);
let res = await as(D, `select * from search_mechanics(6.5146, 3.3760, 2000000, null, 25)`);
ok(res.length === 1 && res[0].id === M, 'search finds the nearby mechanic only');
ok(res[0].distance_km < 2 && res[0].within_budget === true, 'distance and budget flag returned');
res = await as(D, `select * from search_mechanics(6.5146, 3.3760, 1000000, null, 25)`);
ok(res.length === 1 && res[0].within_budget === false, 'over-budget mechanic flagged, still listed');
res = await as(D, `select * from search_mechanics(6.5146, 3.3760, null, 'Tyres', 25)`);
ok(res.length === 0, 'service filter works');

console.log('phase 3: request, accept/reject');
const rid = (await as(D, `select create_request($1,'Battery & electrics','Car won''t start','Herbert Macaulay Way, Yaba',6.5146,3.3760,2000000) id`, [M]))[0].id;
ok(!!rid, 'driver creates a request');
await fails(() => as(D, `select create_request($1,'x','','a',6.5,3.3,null)`, [M]), /already have a request/, 'one active request at a time');
ok((await as(X, `select * from service_requests`)).length === 0, 'other drivers cannot see the request');
ok((await as(M2, `select * from service_requests`)).length === 0, 'other mechanics cannot see the request');
await fails(() => as(M2, `select respond_to_request($1, true, 100, 5)`, [rid]), /not found/, 'only the chosen mechanic can respond');
await fails(() => as(M, `select respond_to_request($1, true, null, 5)`, [rid]), /Enter your price/, 'accepting needs a price');
await fails(() => as(D, `update service_requests set status='completed' where id=$1`, [rid]), /permission denied/, 'apps cannot write statuses directly');
let cp = await as(D, `select * from request_counterpart($1)`, [rid]);
ok(cp[0].display_name === 'Tunde Auto Works' && cp[0].phone === null, 'phone hidden before acceptance');
await fails(() => as(M, `select respond_to_request($1, true, 999999999, 5)`, [rid]), /most you can quote/, 'absurd quotes rejected');
await as(M, `select respond_to_request($1, true, 1800000, 12)`, [rid]);
let r = (await as(D, `select * from service_requests where id=$1`, [rid]))[0];
ok(r.status === 'accepted' && Number(r.quoted_price_kobo) === 1800000 && r.eta_seconds === 720, 'accepted with price and ETA');
cp = await as(D, `select * from request_counterpart($1)`, [rid]);
ok(cp[0].phone === '+2348020000002', 'phone shared after acceptance');

console.log('phase 4: live location visibility');
await as(M, `insert into mechanic_locations (mechanic_id, latitude, longitude) values ($1, 6.51, 3.372)`, [M]);
ok((await as(D, `select * from mechanic_locations`)).length === 1, 'driver sees mechanic during active job');
ok((await as(X, `select * from mechanic_locations`)).length === 0, 'other drivers cannot see the mechanic');
await fails(() => as(D, `insert into mechanic_locations (mechanic_id, latitude, longitude) values ($1,1,1)`, [D]), /row-level security|violates/, 'drivers cannot publish locations');

console.log('phase 5: escrow');
await fails(() => as(D, `select fund_escrow($1)`, [rid]), /Not enough money/, 'cannot pay without balance');
await as(D, `select test_topup(2500000)`);
await as(M, `select update_job_status($1, 'en_route')`, [rid]);
await as(M, `select update_job_status($1, 'arrived')`, [rid]);
await fails(() => as(M, `select update_job_status($1, 'in_progress')`, [rid]), /pay into escrow/, 'work cannot start before escrow is funded');
await as(D, `select fund_escrow($1)`, [rid]);
let wd = (await as(D, `select * from wallet_summary()`))[0];
ok(Number(wd.available_kobo) === 700000 && Number(wd.in_escrow_kobo) === 1800000, 'driver: ₦7,000 available, ₦18,000 in escrow');
let wm = (await as(M, `select * from wallet_summary()`))[0];
ok(Number(wm.available_kobo) === 0 && Number(wm.incoming_kobo) === 1800000, 'mechanic sees ₦18,000 secured but not spendable');
await fails(() => as(D, `select fund_escrow($1)`, [rid]), /already paid/, 'no double payment');
await fails(() => as(D, `select release_escrow($1)`, [rid]), /once the job is complete/, 'no release before completion');
await as(M, `select update_job_status($1, 'in_progress')`, [rid]);
await fails(() => as(D, `select cancel_request($1)`, [rid]), /can't be cancelled/, 'no cancelling once work started');
await as(M, `select update_job_status($1, 'completed')`, [rid]);
await admin(`update app_config set platform_fee_bps = 1000`);
await as(D, `select release_escrow($1)`, [rid]);
wm = (await as(M, `select * from wallet_summary()`))[0];
ok(Number(wm.available_kobo) === 1620000 && Number(wm.incoming_kobo) === 0, 'mechanic paid ₦16,200 after 10% fee');
ok((await admin(`select jobs_completed from mechanic_profiles where id=$1`, [M]))[0].jobs_completed === 1, 'jobs completed counted');
await admin(`update app_config set platform_fee_bps = 0`);

console.log('reviews');
await fails(() => as(X, `insert into reviews (request_id, customer_id, mechanic_id, rating) values ($1,$2,$3,5)`, [rid, X, M]), /row-level security|violates/, 'only the job\'s driver can review');
await as(D, `insert into reviews (request_id, customer_id, mechanic_id, rating, comment) values ($1,$2,$3,4,'Quick and honest')`, [rid, D, M]);
const mp = (await admin(`select rating_avg, rating_count from mechanic_profiles where id=$1`, [M]))[0];
ok(Number(mp.rating_avg) === 4 && mp.rating_count === 1, 'rating average updated');
const rv = await as(X, `select * from mechanic_reviews($1)`, [M]);
ok(rv.length === 1 && rv[0].reviewer === 'Ada' && rv[0].service_type === 'Battery & electrics', 'reviews show first name only');

console.log('cancellation refund');
await as(D, `select test_topup(1000000)`);
const rid2 = (await as(D, `select create_request($1,'Engine repair','','Yaba',6.5146,3.3760,null) id`, [M]))[0].id;
await as(M, `select respond_to_request($1, true, 900000, 10)`, [rid2]);
await as(D, `select fund_escrow($1)`, [rid2]);
await as(M, `select cancel_request($1, 'Car part unavailable')`, [rid2]);
wd = (await as(D, `select * from wallet_summary()`))[0];
ok(Number(wd.available_kobo) === 1700000 && Number(wd.in_escrow_kobo) === 0, 'cancelled job refunded to driver');
ok((await as(D, `select payment_status from service_requests where id=$1`, [rid2]))[0].payment_status === 'refunded', 'payment marked refunded');

console.log('dispute + timeout + reject');
const rid3 = (await as(D, `select create_request($1,'Engine repair','','Yaba',6.5146,3.3760,null) id`, [M]))[0].id;
await as(M, `select respond_to_request($1, false)`, [rid3]);
ok((await as(D, `select status from service_requests where id=$1`, [rid3]))[0].status === 'rejected', 'mechanic can reject');
const rid4 = (await as(D, `select create_request($1,'Engine repair','','Yaba',6.5146,3.3760,null) id`, [M]))[0].id;
await admin(`update service_requests set respond_by = now() - interval '1 second' where id=$1`, [rid4]);
await as(D, `select expire_stale_requests()`);
ok((await as(D, `select status from service_requests where id=$1`, [rid4]))[0].status === 'expired', 'unanswered requests expire');
const rid5 = (await as(D, `select create_request($1,'Engine repair','','Yaba',6.5146,3.3760,null) id`, [M]))[0].id;
await as(M, `select respond_to_request($1, true, 500000, 5)`, [rid5]);
await as(D, `select fund_escrow($1)`, [rid5]);
await as(M, `select update_job_status($1, 'arrived')`, [rid5]);
await as(M, `select update_job_status($1, 'in_progress')`, [rid5]);
await as(M, `select update_job_status($1, 'completed')`, [rid5]);
await as(D, `select dispute_escrow($1, 'Noise came back the same day')`, [rid5]);
ok((await as(M, `select status from escrow_holds where request_id=$1`, [rid5]))[0].status === 'disputed', 'dispute freezes the payment');
await admin(`update service_requests set completed_at = now() - interval '3 days' where id=$1`, [rid5]);
ok((await admin(`select auto_release_escrow() n`))[0].n === 0, 'disputed payments are not auto-released');

console.log('Paystack top-up crediting');
await admin(`insert into payments (reference, user_id, amount_kobo) values ('AW-test-1', $1, 500000)`, [D]);
ok((await admin(`select credit_topup('AW-test-1', 500000, '{}') c`))[0].c === true, 'verified payment credited');
ok((await admin(`select credit_topup('AW-test-1', 500000, '{}') c`))[0].c === false, 'webhook replay does not double-credit');
await fails(() => as(D, `select credit_topup('AW-test-1', 500000, '{}')`), /permission denied/, 'apps cannot credit themselves');

console.log('withdrawals');
await fails(() => as(M, `select request_withdrawal(100000)`), /bank account first/, 'needs a bank account');
await as(M, `select save_payout_account('GTBank','058','0123456789','Tunde Bakare')`);
await fails(() => as(M, `select request_withdrawal(99999999)`), /Not enough money/, 'cannot withdraw more than available');
const wid = (await as(M, `select request_withdrawal(1000000) id`))[0].id;
ok(Number((await as(M, `select * from wallet_summary()`))[0].available_kobo) === 620000, 'withdrawal deducted');
await admin(`select fail_withdrawal($1, 'Bank unavailable')`, [wid]);
ok(Number((await as(M, `select * from wallet_summary()`))[0].available_kobo) === 1620000, 'failed withdrawal returned');

console.log('phase 6: recycling');
const rec = (await as(D, `select submit_recycling('lead_acid_battery', 2, 'Dead', null, 'pickup', null, 'Yaba, Lagos', 6.51, 3.37, current_date + 1) id`))[0].id;
let rr = (await as(D, `select * from recycling_requests where id=$1`, [rec]))[0];
ok(Number(rr.estimated_value_kobo) === 700000 && Number(rr.estimated_co2_kg) === 18, 'estimate: 2 batteries = ₦7,000, 18 kg CO2e');
ok((await as(X, `select * from recycling_requests`)).length === 0, 'others cannot see my recycling');
await fails(() => as(D, `select submit_recycling('tyres', 1, null, null, 'dropoff', null, null, null, null, null)`), /drop-off centre/, 'drop-off needs a centre');
await admin(`update recycling_requests set status='collected' where id=$1`, [rec]);
await admin(`select pay_recycling($1, 650000)`, [rec]);
const imp = (await as(D, `select * from my_recycling_impact()`))[0];
ok(Number(imp.total_paid_kobo) === 650000 && Number(imp.total_co2_kg) === 18, 'recycling paid into wallet; impact totals');

console.log('phase 7: learn history');
await admin(`insert into learn_messages (user_id, role, content) values ($1,'user','What is a battery?')`, [D]);
ok((await as(D, `select * from learn_messages`)).length === 1 && (await as(X, `select * from learn_messages`)).length === 0, 'chat history is private');

console.log(`\nAll ${passed} checks passed.`);
