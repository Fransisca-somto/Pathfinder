import { Request, Response } from 'express';
import { supabase } from '../config/supabase';

// Map Supabase User to our PathFinder UserModel format
const mapToUserModel = (supabaseUser: any, userRole: string = 'owner') => {
  return {
    userId: supabaseUser.id,
    fullName: supabaseUser.user_metadata?.full_name || supabaseUser.email?.split('@')[0] || 'User',
    email: supabaseUser.email,
    phone: supabaseUser.phone || '',
    role: supabaseUser.user_metadata?.role || userRole,
    assignedVehicles: [],
    createdAt: supabaseUser.created_at,
  };
};

export const register = async (req: Request, res: Response): Promise<void> => {
  const { email, password, fullName, phone, role } = req.body;

  try {
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          full_name: fullName,
          phone: phone,
          role: role || 'owner'
        }
      }
    });

    if (error) {
      res.status(400).json({ error: error.message });
      return;
    }

    if (data.user) {
      // Insert into public.users immediately so we can link them to vehicles easily
      await supabase.from('users').insert({
        id: data.user.id,
        email: email,
        full_name: fullName,
        phone: phone || null,
        role: role || 'owner'
      });
    }

    if (data.session && data.user) {
      res.status(201).json({
        token: data.session.access_token,
        user: mapToUserModel(data.user)
      });
      return;
    }

    // In some Supabase configs, email confirmation is required so session might be null
    res.status(200).json({ 
      message: 'Registration successful. Please check your email for confirmation.',
      user: data.user ? mapToUserModel(data.user) : null
    });
  } catch (err: any) {
    res.status(500).json({ error: err.message || 'Internal server error' });
  }
};

export const login = async (req: Request, res: Response): Promise<void> => {
  const { email, password } = req.body;

  try {
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password
    });

    if (error) {
      res.status(401).json({ error: error.message });
      return;
    }

    if (data.session && data.user) {
      res.status(200).json({
        token: data.session.access_token,
        user: mapToUserModel(data.user)
      });
      return;
    }
  } catch (err: any) {
    res.status(500).json({ error: err.message || 'Internal server error' });
  }
};

export const getCurrentUser = async (req: Request, res: Response): Promise<void> => {
  // req.user is attached by the authenticateUser middleware
  if (!req.user) {
    res.status(401).json({ error: 'Not authenticated' });
    return;
  }

  res.status(200).json({
    user: mapToUserModel(req.user)
  });
};
