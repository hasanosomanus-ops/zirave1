-- ZİRAVE Platform Seed Data
-- This file contains initial data for development and testing

-- Insert sample profiles (these will be created after auth users are created)
-- Note: In production, profiles are created via triggers when users sign up

-- Sample categories for products
INSERT INTO public.product_categories (name, description) VALUES
('Sebze', 'Taze sebzeler ve yeşillikler'),
('Meyve', 'Mevsim meyveleri'),
('Tahıl', 'Buğday, arpa, mısır ve diğer tahıllar'),
('Baklagil', 'Fasulye, nohut, mercimek'),
('Süt Ürünleri', 'Süt, peynir, yoğurt'),
('Et Ürünleri', 'Kırmızı et, beyaz et'),
('Tohum', 'Ekim için tohumlar'),
('Gübre', 'Organik ve kimyasal gübreler'),
('İlaç', 'Tarımsal ilaçlar ve koruyucular'),
('Makine', 'Tarım makineleri ve ekipmanları')
ON CONFLICT (name) DO NOTHING;

-- Sample products (will be linked to actual users after they register)
-- These are placeholder products for development
INSERT INTO public.products (name, description, price, category, supplier_id, is_active) VALUES
('Organik Domates', 'Sera yetiştiriciliği, pestisitsiz', 15.50, 'Sebze', '00000000-0000-0000-0000-000000000000', true),
('Taze Salatalık', 'Günlük hasat, crispy', 8.00, 'Sebze', '00000000-0000-0000-0000-000000000000', true),
('Kırmızı Elma', 'Amasya elması, doğal', 12.00, 'Meyve', '00000000-0000-0000-0000-000000000000', true),
('Buğday', '1. kalite buğday, temiz', 2.50, 'Tahıl', '00000000-0000-0000-0000-000000000000', true),
('Organik Gübre', 'Hayvan gübresi, kompost', 45.00, 'Gübre', '00000000-0000-0000-0000-000000000000', true)
ON CONFLICT DO NOTHING;