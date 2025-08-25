/*
  # Add Message Moderation System

  1. New Tables
    - `moderated_messages`
      - `id` (uuid, primary key)
      - `original_message_id` (uuid, references messages.id)
      - `original_content` (text)
      - `moderated_content` (text)
      - `flagged_patterns` (text array)
      - `is_appropriate` (boolean)
      - `confidence` (decimal)
      - `created_at` (timestamp)

  2. Functions
    - `moderate_message_content()` - Function to call Edge Function for moderation
    - `handle_new_message()` - Trigger function for automatic moderation

  3. Triggers
    - Trigger on messages table to automatically moderate content

  4. Security
    - Enable RLS on moderated_messages table
    - Add policies for admin access
*/

-- Create moderated_messages table
CREATE TABLE IF NOT EXISTS moderated_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  original_message_id uuid REFERENCES messages(id) ON DELETE CASCADE,
  original_content text NOT NULL,
  moderated_content text NOT NULL,
  flagged_patterns text[] DEFAULT '{}',
  is_appropriate boolean DEFAULT true,
  confidence decimal(3,2) DEFAULT 0.99,
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE moderated_messages ENABLE ROW LEVEL SECURITY;

-- Admin-only access policy
CREATE POLICY "Only admins can access moderated messages"
  ON moderated_messages
  FOR ALL
  TO authenticated
  USING (false); -- This will be updated when admin roles are implemented

-- Function to call the moderation Edge Function
CREATE OR REPLACE FUNCTION moderate_message_content(content_text text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result jsonb;
BEGIN
  -- Call the Edge Function (this is a placeholder - actual implementation would use HTTP)
  -- For now, we'll do basic moderation in SQL
  
  -- Simple phone number detection
  IF content_text ~* '(\+90\s?)?(\(0?\d{3}\)\s?|\d{3}[-.\s]?)\d{3}[-.\s]?\d{2}[-.\s]?\d{2}' THEN
    result := jsonb_build_object(
      'isAppropriate', false,
      'originalContent', content_text,
      'moderatedContent', regexp_replace(content_text, '(\+90\s?)?(\(0?\d{3}\)\s?|\d{3}[-.\s]?)\d{3}[-.\s]?\d{2}[-.\s]?\d{2}', '[İletişim bilgisi güvenlik nedeniyle kaldırıldı]', 'gi'),
      'flaggedPatterns', ARRAY['Phone number'],
      'confidence', 0.95
    );
  -- Simple email detection
  ELSIF content_text ~* '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' THEN
    result := jsonb_build_object(
      'isAppropriate', false,
      'originalContent', content_text,
      'moderatedContent', regexp_replace(content_text, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', '[E-posta adresi güvenlik nedeniyle kaldırıldı]', 'gi'),
      'flaggedPatterns', ARRAY['Email address'],
      'confidence', 0.95
    );
  ELSE
    result := jsonb_build_object(
      'isAppropriate', true,
      'originalContent', content_text,
      'moderatedContent', content_text,
      'flaggedPatterns', ARRAY[]::text[],
      'confidence', 0.99
    );
  END IF;
  
  RETURN result;
END;
$$;

-- Function to handle new message moderation
CREATE OR REPLACE FUNCTION handle_new_message()
RETURNS trigger AS $$
DECLARE
  moderation_result jsonb;
BEGIN
  -- Moderate the message content
  moderation_result := moderate_message_content(NEW.content);
  
  -- Update the message with moderated content if needed
  IF NOT (moderation_result->>'isAppropriate')::boolean THEN
    NEW.content := moderation_result->>'moderatedContent';
    
    -- Log the moderation
    INSERT INTO moderated_messages (
      original_message_id,
      original_content,
      moderated_content,
      flagged_patterns,
      is_appropriate,
      confidence
    ) VALUES (
      NEW.id,
      moderation_result->>'originalContent',
      moderation_result->>'moderatedContent',
      ARRAY(SELECT jsonb_array_elements_text(moderation_result->'flaggedPatterns')),
      (moderation_result->>'isAppropriate')::boolean,
      (moderation_result->>'confidence')::decimal
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for automatic message moderation
DROP TRIGGER IF EXISTS moderate_messages_trigger ON messages;
CREATE TRIGGER moderate_messages_trigger
  BEFORE INSERT ON messages
  FOR EACH ROW EXECUTE FUNCTION handle_new_message();

-- Index for performance
CREATE INDEX IF NOT EXISTS moderated_messages_message_id_idx ON moderated_messages(original_message_id);
CREATE INDEX IF NOT EXISTS moderated_messages_created_at_idx ON moderated_messages(created_at);
CREATE INDEX IF NOT EXISTS moderated_messages_is_appropriate_idx ON moderated_messages(is_appropriate);