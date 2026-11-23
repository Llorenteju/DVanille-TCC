-- D'VANILLE: ADICIONA tabelas para vale-presente e comanda presencial.
-- PostgreSQL / Supabase. Executar SOMENTE após backup e confirmação do banco usado pela API.
-- NÃO altera tabelas de reservas, pedidos do Mobile ou usuários.
BEGIN;
CREATE TABLE IF NOT EXISTS gift_vouchers (
  id VARCHAR(36) PRIMARY KEY,
  code VARCHAR(32) NOT NULL UNIQUE,
  buyer_id INTEGER NOT NULL,
  buyer_email VARCHAR(191) NOT NULL,
  face_value_cents INTEGER NOT NULL CHECK (face_value_cents > 0),
  recipient VARCHAR(120) NOT NULL,
  message TEXT NOT NULL DEFAULT '',
  status VARCHAR(20) NOT NULL DEFAULT 'ativo' CHECK (status IN ('ativo','utilizado','cancelado')),
  expires_at TIMESTAMPTZ NOT NULL,
  redeemed_at TIMESTAMPTZ NULL,
  client_request_id VARCHAR(80) NOT NULL,
  item_index INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_voucher_request_item UNIQUE (buyer_id, client_request_id, item_index)
);
CREATE INDEX IF NOT EXISTS ix_voucher_buyer ON gift_vouchers (buyer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_voucher_status ON gift_vouchers (status, expires_at);
CREATE TABLE IF NOT EXISTS table_orders (
  id VARCHAR(36) PRIMARY KEY,
  client_request_id VARCHAR(80) NOT NULL UNIQUE,
  table_label VARCHAR(16) NOT NULL,
  user_id INTEGER NOT NULL,
  buyer_email VARCHAR(191) NOT NULL,
  subtotal_cents INTEGER NOT NULL CHECK (subtotal_cents >= 0),
  discount_cents INTEGER NOT NULL DEFAULT 0 CHECK (discount_cents >= 0),
  total_cents INTEGER NOT NULL CHECK (total_cents >= 0),
  status VARCHAR(24) NOT NULL DEFAULT 'recebido',
  coupon VARCHAR(32) NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_table_orders_user ON table_orders (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_table_orders_table ON table_orders (table_label, created_at DESC);
CREATE TABLE IF NOT EXISTS table_order_items (
  id VARCHAR(36) PRIMARY KEY,
  table_order_id VARCHAR(36) NOT NULL REFERENCES table_orders(id),
  product_id INTEGER NOT NULL,
  product_name VARCHAR(200) NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity BETWEEN 1 AND 30),
  unit_price_cents INTEGER NOT NULL CHECK (unit_price_cents > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_table_order_items_order ON table_order_items (table_order_id);
-- Acesso direto por Supabase anon/authenticated é bloqueado; as rotas Node
-- são a interface de acesso. Revisar a role da conexão Prisma antes de aplicar.
ALTER TABLE gift_vouchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE table_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE table_order_items ENABLE ROW LEVEL SECURITY;
COMMIT;
