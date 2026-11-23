-- D'VANILLE: ADICIONA tabelas para vale-presente e comanda presencial.
-- MySQL. Executar SOMENTE após backup e confirmação do banco usado pela API.
-- NOTA: DDL MySQL não é completamente transacional. Backup obrigatório.
CREATE TABLE IF NOT EXISTS gift_vouchers (
  id VARCHAR(36) NOT NULL PRIMARY KEY,
  code VARCHAR(32) NOT NULL UNIQUE,
  buyer_id INT NOT NULL,
  buyer_email VARCHAR(191) NOT NULL,
  face_value_cents INT NOT NULL,
  recipient VARCHAR(120) NOT NULL,
  message TEXT NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'ativo',
  expires_at DATETIME(3) NOT NULL,
  redeemed_at DATETIME(3) NULL,
  client_request_id VARCHAR(80) NOT NULL,
  item_index INT NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE KEY uq_voucher_request_item (buyer_id, client_request_id, item_index),
  KEY ix_voucher_buyer (buyer_id, created_at),
  KEY ix_voucher_status (status, expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS table_orders (
  id VARCHAR(36) NOT NULL PRIMARY KEY,
  client_request_id VARCHAR(80) NOT NULL UNIQUE,
  table_label VARCHAR(16) NOT NULL,
  user_id INT NOT NULL,
  buyer_email VARCHAR(191) NOT NULL,
  subtotal_cents INT NOT NULL,
  discount_cents INT NOT NULL DEFAULT 0,
  total_cents INT NOT NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'recebido',
  coupon VARCHAR(32) NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  KEY ix_table_orders_user (user_id, created_at),
  KEY ix_table_orders_table (table_label, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS table_order_items (
  id VARCHAR(36) NOT NULL PRIMARY KEY,
  table_order_id VARCHAR(36) NOT NULL,
  product_id INT NOT NULL,
  product_name VARCHAR(200) NOT NULL,
  quantity INT NOT NULL,
  unit_price_cents INT NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  KEY ix_table_order_items_order (table_order_id),
  CONSTRAINT fk_table_order_items_order FOREIGN KEY (table_order_id) REFERENCES table_orders(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
