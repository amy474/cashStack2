-- Crash, hang and resource reports from MetricKit. They arrive without a
-- token and are stored without a user or an IP address, so nothing here can
-- be traced back to a person. Kept for 90 days.
create table diagnostics (
  id bigint generated always as identity primary key,
  -- crash, hang, cpu, disk_write or launch
  kind text not null,
  app_version text,
  app_build text,
  os_version text,
  device_type text,
  -- One line a person can read: "EXC_BAD_ACCESS (SIGSEGV)", "2.4s hang".
  summary text not null,
  -- The diagnostic as MetricKit wrote it, call stacks and all.
  detail jsonb not null,
  received_at timestamptz not null default now()
);
create index diagnostics_received on diagnostics (received_at);
create index diagnostics_build on diagnostics (app_build, kind);
