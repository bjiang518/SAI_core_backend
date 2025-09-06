-- StudyAI Database Schema for Supabase
-- Run this in your Supabase SQL Editor

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users table (extends Supabase auth.users)
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users(id) PRIMARY KEY,
  email VARCHAR UNIQUE NOT NULL,
  role VARCHAR CHECK (role IN ('student', 'parent')) NOT NULL,
  parent_id UUID REFERENCES public.profiles(id),
  first_name VARCHAR(50),
  last_name VARCHAR(50),
  date_of_birth DATE,
  grade_level INTEGER,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  profile_settings JSONB DEFAULT '{}'::jsonb
);

-- Questions table
CREATE TABLE public.questions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.profiles(id) NOT NULL,
  session_id UUID,
  image_url TEXT,
  image_data BYTEA,
  question_text TEXT,
  subject VARCHAR(50),
  topic VARCHAR(100),
  difficulty_level INTEGER CHECK (difficulty_level BETWEEN 1 AND 5),
  ai_solution JSONB,
  explanation JSONB,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Sessions table (homework sessions)
CREATE TABLE public.sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.profiles(id) NOT NULL,
  parent_id UUID REFERENCES public.profiles(id),
  session_type VARCHAR CHECK (session_type IN ('homework', 'practice', 'mock_exam')) NOT NULL,
  title VARCHAR(200),
  description TEXT,
  start_time TIMESTAMP DEFAULT NOW(),
  end_time TIMESTAMP,
  total_questions INTEGER DEFAULT 0,
  completed_questions INTEGER DEFAULT 0,
  status VARCHAR CHECK (status IN ('active', 'completed', 'paused')) DEFAULT 'active',
  metadata JSONB DEFAULT '{}'::jsonb
);

-- Add session_id foreign key to questions
ALTER TABLE public.questions 
ADD CONSTRAINT fk_questions_session 
FOREIGN KEY (session_id) REFERENCES public.sessions(id) ON DELETE SET NULL;

-- Student answers and evaluations
CREATE TABLE public.evaluations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id UUID REFERENCES public.sessions(id) NOT NULL,
  question_id UUID REFERENCES public.questions(id) NOT NULL,
  student_answer TEXT,
  student_answer_image BYTEA,
  ai_feedback JSONB,
  score DECIMAL(4,2) CHECK (score >= 0 AND score <= 100),
  time_spent INTEGER, -- seconds
  attempts INTEGER DEFAULT 1,
  is_correct BOOLEAN,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Progress tracking table
CREATE TABLE public.progress (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.profiles(id) NOT NULL,
  subject VARCHAR(50) NOT NULL,
  topic VARCHAR(100),
  skill_area VARCHAR(100),
  strength_score DECIMAL(4,2) CHECK (strength_score >= 0 AND strength_score <= 100),
  total_attempts INTEGER DEFAULT 0,
  correct_answers INTEGER DEFAULT 0,
  average_time INTEGER, -- average seconds per question
  last_practiced TIMESTAMP,
  mastery_level VARCHAR CHECK (mastery_level IN ('beginner', 'intermediate', 'advanced', 'mastered')) DEFAULT 'beginner',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, subject, topic, skill_area)
);

-- Conversations table (for chat feature)
CREATE TABLE public.conversations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.profiles(id) NOT NULL,
  question_id UUID REFERENCES public.questions(id),
  message_type VARCHAR CHECK (message_type IN ('user', 'ai')) NOT NULL,
  message_text TEXT NOT NULL,
  message_data JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Mock exams table
CREATE TABLE public.mock_exams (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.profiles(id) NOT NULL,
  title VARCHAR(200) NOT NULL,
  subject VARCHAR(50),
  difficulty_level INTEGER CHECK (difficulty_level BETWEEN 1 AND 5),
  time_limit INTEGER, -- minutes
  total_questions INTEGER,
  passing_score DECIMAL(4,2),
  generated_questions JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Mock exam attempts
CREATE TABLE public.mock_exam_attempts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  exam_id UUID REFERENCES public.mock_exams(id) NOT NULL,
  user_id UUID REFERENCES public.profiles(id) NOT NULL,
  start_time TIMESTAMP DEFAULT NOW(),
  end_time TIMESTAMP,
  score DECIMAL(4,2),
  answers JSONB,
  time_taken INTEGER, -- minutes
  is_completed BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Educational content links
CREATE TABLE public.educational_content (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  question_id UUID REFERENCES public.questions(id),
  content_type VARCHAR CHECK (content_type IN ('video', 'article', 'tutorial')) NOT NULL,
  title VARCHAR(300),
  url TEXT NOT NULL,
  platform VARCHAR(50), -- youtube, khan_academy, etc.
  duration INTEGER, -- seconds for videos
  difficulty_level INTEGER CHECK (difficulty_level BETWEEN 1 AND 5),
  subject VARCHAR(50),
  topic VARCHAR(100),
  created_at TIMESTAMP DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX idx_profiles_parent_id ON public.profiles(parent_id);
CREATE INDEX idx_questions_user_id ON public.questions(user_id);
CREATE INDEX idx_questions_session_id ON public.questions(session_id);
CREATE INDEX idx_questions_subject ON public.questions(subject);
CREATE INDEX idx_sessions_user_id ON public.sessions(user_id);
CREATE INDEX idx_sessions_parent_id ON public.sessions(parent_id);
CREATE INDEX idx_evaluations_session_id ON public.evaluations(session_id);
CREATE INDEX idx_evaluations_question_id ON public.evaluations(question_id);
CREATE INDEX idx_progress_user_id ON public.progress(user_id);
CREATE INDEX idx_progress_subject ON public.progress(subject);
CREATE INDEX idx_conversations_user_id ON public.conversations(user_id);
CREATE INDEX idx_conversations_question_id ON public.conversations(question_id);

-- Row Level Security (RLS) policies
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.evaluations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mock_exams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mock_exam_attempts ENABLE ROW LEVEL SECURITY;

-- RLS Policies for profiles
CREATE POLICY "Users can view own profile" ON public.profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON public.profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Parents can view their children's profiles" ON public.profiles
  FOR SELECT USING (auth.uid() = parent_id);

-- RLS Policies for questions
CREATE POLICY "Users can view own questions" ON public.questions
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Parents can view children's questions" ON public.questions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE profiles.id = questions.user_id 
      AND profiles.parent_id = auth.uid()
    )
  );

-- RLS Policies for sessions
CREATE POLICY "Users can manage own sessions" ON public.sessions
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Parents can view children's sessions" ON public.sessions
  FOR SELECT USING (auth.uid() = parent_id);

-- RLS Policies for evaluations
CREATE POLICY "Users can view own evaluations" ON public.evaluations
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.sessions 
      WHERE sessions.id = evaluations.session_id 
      AND sessions.user_id = auth.uid()
    )
  );

CREATE POLICY "Parents can view children's evaluations" ON public.evaluations
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.sessions 
      WHERE sessions.id = evaluations.session_id 
      AND sessions.parent_id = auth.uid()
    )
  );

-- RLS Policies for progress
CREATE POLICY "Users can view own progress" ON public.progress
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Parents can view children's progress" ON public.progress
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE profiles.id = progress.user_id 
      AND profiles.parent_id = auth.uid()
    )
  );

-- Functions for automatic timestamp updates
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for updated_at
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_questions_updated_at BEFORE UPDATE ON public.questions FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_evaluations_updated_at BEFORE UPDATE ON public.evaluations FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_progress_updated_at BEFORE UPDATE ON public.progress FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- Insert some sample data for testing
INSERT INTO public.profiles (id, email, role, first_name, last_name, grade_level) VALUES
  ('00000000-0000-0000-0000-000000000001', 'parent@example.com', 'parent', 'John', 'Doe', NULL),
  ('00000000-0000-0000-0000-000000000002', 'student@example.com', 'student', 'Jane', 'Doe', 8);

-- Update student to link with parent
UPDATE public.profiles 
SET parent_id = '00000000-0000-0000-0000-000000000001' 
WHERE id = '00000000-0000-0000-0000-000000000002';