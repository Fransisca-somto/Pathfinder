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
      console.error('[Register] Supabase signUp error:', error.message, error);
      // Supabase returns code 'user_already_exists' (422) when the email is taken.
      // Map it to a clean 409 so the client can show a sensible message.
      if ((error as any).code === 'user_already_exists') {
        res.status(409).json({ error: 'An account with this email already exists. Please log in instead.' });
        return;
      }
      res.status(400).json({ error: error.message });
      return;
    }

    if (data.user) {
      // Insert into public.users immediately so we can link them to vehicles easily
      const { error: profileError } = await supabase.from('users').insert({
        id: data.user.id,
        email: email,
        full_name: fullName,
        phone: phone || null,
        role: role || 'owner'
      });
      
      if (profileError) {
        console.error('[Register] Failed to create public.users profile:', profileError);
      }
    }

    if (data.session && data.user) {
      res.status(201).json({
        token:         data.session.access_token,
        refresh_token: data.session.refresh_token,
        expires_in:    data.session.expires_in,
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
        token:         data.session.access_token,
        refresh_token: data.session.refresh_token,
        expires_in:    data.session.expires_in,
        user: mapToUserModel(data.user)
      });
      return;
    }
  } catch (err: any) {
    res.status(500).json({ error: err.message || 'Internal server error' });
  }
};

// POST /auth/refresh — exchange a valid refresh token for a new access token.
// Supabase rotates the refresh token on every use, so the response always
// carries a new refresh_token that must replace the stored one.
export const refreshToken = async (req: Request, res: Response): Promise<void> => {
  const { refresh_token } = req.body;
  if (!refresh_token) {
    res.status(400).json({ error: 'refresh_token is required' });
    return;
  }

  try {
    const { data, error } = await supabase.auth.refreshSession({ refresh_token });

    if (error || !data.session) {
      console.warn('[Auth] Refresh failed:', error?.message);
      res.status(401).json({ error: 'Invalid or expired refresh token' });
      return;
    }

    res.status(200).json({
      token:         data.session.access_token,
      refresh_token: data.session.refresh_token, // rotated — client must persist this
      expires_in:    data.session.expires_in,
    });
  } catch (err: any) {
    res.status(500).json({ error: err.message || 'Internal server error' });
  }
};

// POST /auth/logout — revokes the refresh token for THIS session only.
// Using 'local' scope means the user's other devices (tablet, laptop, etc.)
// stay signed in. The revoked refresh token cannot be replayed after this call.
export const logout = async (req: Request, res: Response): Promise<void> => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader) {
      res.status(204).send();
      return;
    }
    
    const accessToken = authHeader.split(' ')[1];
    if (!accessToken) {
      res.status(204).send();
      return;
    }

    // admin.signOut(jwt, 'local') revokes only the refresh token that this
    // access token belongs to — all other sessions for this user are untouched.
    const { error } = await supabase.auth.admin.signOut(accessToken, 'local');
    if (error) {
      console.warn('[Auth] Server-side signOut returned error:', error.message);
    } else {
      console.log('[Auth] Session revoked server-side for token prefix:', accessToken.substring(0, 10));
    }
  } catch (err) {
    // Best-effort — always respond 204 so the client still clears its state
    console.warn('[Auth] Server-side signOut threw:', err);
  }

  res.status(204).send();
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
