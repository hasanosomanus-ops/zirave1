/*
  # Logistics System Database Schema

  1. New Tables
    - `vehicles`
      - `id` (uuid, primary key)
      - `driver_id` (uuid, references profiles.id)
      - `vehicle_type` (enum: TRUCK, TRACTOR, VAN, PICKUP)
      - `license_plate` (text, unique)
      - `capacity_kg` (integer)
      - `capacity_m3` (decimal)
      - `is_available` (boolean)
      - `current_location` (text)
      - `created_at` (timestamp)
      - `updated_at` (timestamp)
    
    - `shipment_requests`
      - `id` (uuid, primary key)
      - `requester_id` (uuid, references profiles.id)
      - `title` (text)
      - `description` (text)
      - `pickup_location` (text)
      - `dropoff_location` (text)
      - `cargo_weight_kg` (integer)
      - `cargo_volume_m3` (decimal)
      - `preferred_pickup_date` (date)
      - `max_budget` (decimal)
      - `status` (enum: OPEN, ASSIGNED, IN_TRANSIT, DELIVERED, CANCELLED)
      - `created_at` (timestamp)
      - `updated_at` (timestamp)
    
    - `shipment_bids`
      - `id` (uuid, primary key)
      - `shipment_request_id` (uuid, references shipment_requests.id)
      - `driver_id` (uuid, references profiles.id)
      - `vehicle_id` (uuid, references vehicles.id)
      - `bid_amount` (decimal)
      - `estimated_pickup_date` (date)
      - `estimated_delivery_date` (date)
      - `message` (text)
      - `status` (enum: PENDING, ACCEPTED, REJECTED, WITHDRAWN)
      - `created_at` (timestamp)
      - `updated_at` (timestamp)

  2. Security
    - Enable RLS on all new tables
    - Add policies for drivers to manage their vehicles and bids
    - Add policies for requesters to manage their shipment requests
    - Add policies for viewing active shipments and bids

  3. Enums and Constraints
    - Vehicle type constraints
    - Shipment status workflow
    - Bid status management
*/

-- Create custom types for logistics
CREATE TYPE vehicle_type AS ENUM ('TRUCK', 'TRACTOR', 'VAN', 'PICKUP');
CREATE TYPE shipment_status AS ENUM ('OPEN', 'ASSIGNED', 'IN_TRANSIT', 'DELIVERED', 'CANCELLED');
CREATE TYPE bid_status AS ENUM ('PENDING', 'ACCEPTED', 'REJECTED', 'WITHDRAWN');

-- Create vehicles table
CREATE TABLE IF NOT EXISTS vehicles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id uuid REFERENCES profiles(id) ON DELETE CASCADE,
  vehicle_type vehicle_type NOT NULL,
  license_plate text UNIQUE NOT NULL,
  capacity_kg integer DEFAULT 0,
  capacity_m3 decimal(8,2) DEFAULT 0.0,
  is_available boolean DEFAULT true,
  current_location text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create shipment_requests table
CREATE TABLE IF NOT EXISTS shipment_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id uuid REFERENCES profiles(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text,
  pickup_location text NOT NULL,
  dropoff_location text NOT NULL,
  cargo_weight_kg integer DEFAULT 0,
  cargo_volume_m3 decimal(8,2) DEFAULT 0.0,
  preferred_pickup_date date,
  max_budget decimal(10,2),
  status shipment_status DEFAULT 'OPEN',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create shipment_bids table
CREATE TABLE IF NOT EXISTS shipment_bids (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_request_id uuid REFERENCES shipment_requests(id) ON DELETE CASCADE,
  driver_id uuid REFERENCES profiles(id) ON DELETE CASCADE,
  vehicle_id uuid REFERENCES vehicles(id) ON DELETE CASCADE,
  bid_amount decimal(10,2) NOT NULL,
  estimated_pickup_date date,
  estimated_delivery_date date,
  message text,
  status bid_status DEFAULT 'PENDING',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(shipment_request_id, driver_id)
);

-- Enable Row Level Security
ALTER TABLE vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE shipment_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE shipment_bids ENABLE ROW LEVEL SECURITY;

-- Vehicles policies
CREATE POLICY "Drivers can manage own vehicles"
  ON vehicles
  FOR ALL
  TO authenticated
  USING (auth.uid() = driver_id);

CREATE POLICY "Anyone can view available vehicles"
  ON vehicles
  FOR SELECT
  TO authenticated
  USING (is_available = true);

-- Shipment requests policies
CREATE POLICY "Requesters can manage own shipment requests"
  ON shipment_requests
  FOR ALL
  TO authenticated
  USING (auth.uid() = requester_id);

CREATE POLICY "Drivers can view open shipment requests"
  ON shipment_requests
  FOR SELECT
  TO authenticated
  USING (status = 'OPEN');

-- Shipment bids policies
CREATE POLICY "Drivers can manage own bids"
  ON shipment_bids
  FOR ALL
  TO authenticated
  USING (auth.uid() = driver_id);

CREATE POLICY "Requesters can view bids on their shipments"
  ON shipment_bids
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM shipment_requests
      WHERE shipment_requests.id = shipment_bids.shipment_request_id
      AND shipment_requests.requester_id = auth.uid()
    )
  );

CREATE POLICY "Requesters can update bid status"
  ON shipment_bids
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM shipment_requests
      WHERE shipment_requests.id = shipment_bids.shipment_request_id
      AND shipment_requests.requester_id = auth.uid()
    )
  );

-- Triggers for updated_at
CREATE TRIGGER vehicles_updated_at
  BEFORE UPDATE ON vehicles
  FOR EACH ROW EXECUTE PROCEDURE public.handle_updated_at();

CREATE TRIGGER shipment_requests_updated_at
  BEFORE UPDATE ON shipment_requests
  FOR EACH ROW EXECUTE PROCEDURE public.handle_updated_at();

CREATE TRIGGER shipment_bids_updated_at
  BEFORE UPDATE ON shipment_bids
  FOR EACH ROW EXECUTE PROCEDURE public.handle_updated_at();

-- Indexes for performance
CREATE INDEX IF NOT EXISTS vehicles_driver_id_idx ON vehicles(driver_id);
CREATE INDEX IF NOT EXISTS vehicles_available_idx ON vehicles(is_available);
CREATE INDEX IF NOT EXISTS vehicles_type_idx ON vehicles(vehicle_type);

CREATE INDEX IF NOT EXISTS shipment_requests_requester_idx ON shipment_requests(requester_id);
CREATE INDEX IF NOT EXISTS shipment_requests_status_idx ON shipment_requests(status);
CREATE INDEX IF NOT EXISTS shipment_requests_pickup_date_idx ON shipment_requests(preferred_pickup_date);

CREATE INDEX IF NOT EXISTS shipment_bids_request_idx ON shipment_bids(shipment_request_id);
CREATE INDEX IF NOT EXISTS shipment_bids_driver_idx ON shipment_bids(driver_id);
CREATE INDEX IF NOT EXISTS shipment_bids_status_idx ON shipment_bids(status);

-- Function to automatically update shipment status when bid is accepted
CREATE OR REPLACE FUNCTION handle_bid_acceptance()
RETURNS trigger AS $$
BEGIN
  -- When a bid is accepted, update the shipment request status
  IF NEW.status = 'ACCEPTED' AND OLD.status != 'ACCEPTED' THEN
    UPDATE shipment_requests 
    SET status = 'ASSIGNED'
    WHERE id = NEW.shipment_request_id;
    
    -- Reject all other bids for this shipment
    UPDATE shipment_bids 
    SET status = 'REJECTED'
    WHERE shipment_request_id = NEW.shipment_request_id 
    AND id != NEW.id 
    AND status = 'PENDING';
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for bid acceptance
CREATE TRIGGER handle_bid_acceptance_trigger
  AFTER UPDATE ON shipment_bids
  FOR EACH ROW EXECUTE FUNCTION handle_bid_acceptance();