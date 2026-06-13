-- =============================================
-- BIBLIOTHEQUE APP — Schéma Supabase
-- À exécuter dans l'éditeur SQL Supabase
-- =============================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ----------------------
-- PROFILES (linked to auth.users)
-- ----------------------
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Auto-create profile on user signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, email, name, avatar_url)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    NEW.raw_user_meta_data->>'avatar_url'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ----------------------
-- LIBRARIES
-- ----------------------
CREATE TABLE libraries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL DEFAULT 'Ma Bibliothèque',
  owner_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------
-- LIBRARY MEMBERS
-- ----------------------
CREATE TABLE library_members (
  library_id UUID REFERENCES libraries(id) ON DELETE CASCADE,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  role TEXT DEFAULT 'member' CHECK (role IN ('owner', 'member')),
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (library_id, user_id)
);

-- ----------------------
-- BOOKS
-- ----------------------
CREATE TABLE books (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  library_id UUID REFERENCES libraries(id) ON DELETE CASCADE,
  isbn TEXT,
  title TEXT NOT NULL,
  authors TEXT[] DEFAULT '{}',
  cover_url TEXT,
  publisher TEXT,
  published_year INTEGER,
  page_count INTEGER,
  genre TEXT,
  description TEXT,
  book_type TEXT DEFAULT 'livre' CHECK (book_type IN ('livre', 'bd', 'manga')),
  status TEXT DEFAULT 'a_lire' CHECK (status IN ('lu', 'en_cours', 'a_lire')),
  rating INTEGER CHECK (rating BETWEEN 1 AND 5),
  note TEXT,
  added_by UUID REFERENCES profiles(id),
  added_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast search
CREATE INDEX books_library_id_idx ON books(library_id);
CREATE INDEX books_isbn_idx ON books(isbn);
CREATE INDEX books_status_idx ON books(status);
CREATE INDEX books_title_idx ON books USING GIN(to_tsvector('french', title));

-- ----------------------
-- ROW LEVEL SECURITY
-- ----------------------
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE libraries ENABLE ROW LEVEL SECURITY;
ALTER TABLE library_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE books ENABLE ROW LEVEL SECURITY;

-- Profiles: each user sees/edits only their own
CREATE POLICY "Users can view their profile" ON profiles
  FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update their profile" ON profiles
  FOR UPDATE USING (auth.uid() = id);

-- Libraries: members can view, owner can edit/delete
CREATE POLICY "Members can view library" ON libraries
  FOR SELECT USING (
    id IN (
      SELECT library_id FROM library_members WHERE user_id = auth.uid()
    )
  );
CREATE POLICY "Owner can update library" ON libraries
  FOR UPDATE USING (owner_id = auth.uid());
CREATE POLICY "Owner can delete library" ON libraries
  FOR DELETE USING (owner_id = auth.uid());
CREATE POLICY "Authenticated users can create library" ON libraries
  FOR INSERT WITH CHECK (auth.uid() = owner_id);

-- Library members: members can view other members
CREATE POLICY "Members can view membership" ON library_members
  FOR SELECT USING (
    library_id IN (
      SELECT library_id FROM library_members WHERE user_id = auth.uid()
    )
  );
CREATE POLICY "Owner can manage members" ON library_members
  FOR ALL USING (
    library_id IN (
      SELECT id FROM libraries WHERE owner_id = auth.uid()
    )
  );
CREATE POLICY "Users can join a library" ON library_members
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Books: all library members can read and add books
CREATE POLICY "Members can view books" ON books
  FOR SELECT USING (
    library_id IN (
      SELECT library_id FROM library_members WHERE user_id = auth.uid()
    )
  );
CREATE POLICY "Members can add books" ON books
  FOR INSERT WITH CHECK (
    library_id IN (
      SELECT library_id FROM library_members WHERE user_id = auth.uid()
    )
  );
CREATE POLICY "Members can update books" ON books
  FOR UPDATE USING (
    library_id IN (
      SELECT library_id FROM library_members WHERE user_id = auth.uid()
    )
  );
CREATE POLICY "Members can delete books they added" ON books
  FOR DELETE USING (added_by = auth.uid());
