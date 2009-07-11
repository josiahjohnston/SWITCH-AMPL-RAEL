--##################################################
-- import generation capacity data

drop table if exists gen_cap;
create table gen_cap (
  scenario varchar(25),
  carbon_cost double,
  period year,
  load_area varchar(20),
  technology varchar(10),
  site varchar(30),
  orientation char(3),
  new boolean,
  baseload boolean,
  cogen boolean,
  fuel varchar(20),
  capacity double,
  fixed_cost double);

--##################################################
-- import transmission capacity data

drop table if exists trans_cap;
create table trans_cap (
  scenario varchar(25),
  carbon_cost double,
  period year,
  start varchar(20),
  end varchar(20),
  tid int,
  new boolean,
  trans_mw double,
  fixed_cost double);

--##################################################
-- import local T&D data

drop table if exists local_td_cap;
create table local_td_cap (
  scenario varchar(25),
  carbon_cost double,
  period year,
  load_area varchar(20),
  local_td_mw double,
  fixed_cost double);

--##################################################
-- import hourly power data

drop table if exists dispatch;
create table dispatch (
  scenario varchar(25),
  carbon_cost double,
  period int,
  load_area varchar(20),
  study_date int,
  study_hour int,
  technology varchar(10),
  site varchar(30),
  orientation char(3),
  new boolean,
  baseload boolean,
  cogen boolean,
  fuel varchar(20),
  power double,
  co2_tons double,
  hours_in_sample smallint,
  heat_rate double, 
  fuel_cost_tot double,
  carbon_cost_tot double,
  variable_o_m_tot double
);

--##################################################
-- import hourly power transmission between zones
drop table if exists transmission;
create table transmission (
  scenario varchar(25),
  carbon_cost double,
  period int,
  load_area_receive varchar(20),
  load_area_from varchar(20),
  study_date int,
  study_hour int,
  power double,
  hours_in_sample smallint
);