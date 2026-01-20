import { useDispatch, useSelector } from 'react-redux';
import type { RootState, AppDispatch } from '../store';
import { login, logout, register, clearError } from '../store/authSlice';
import type { LoginCredentials, RegisterData } from '../types';

export const useAuth = () => {
  const dispatch = useDispatch<AppDispatch>();
  const { isAuthenticated, loading, error } = useSelector(
    (state: RootState) => state.auth
  );

  const handleLogin = async (credentials: LoginCredentials) => {
    return dispatch(login(credentials));
  };

  const handleRegister = async (data: RegisterData) => {
    return dispatch(register(data));
  };

  const handleLogout = async () => {
    return dispatch(logout());
  };

  const handleClearError = () => {
    dispatch(clearError());
  };

  return {
    isAuthenticated,
    loading,
    error,
    login: handleLogin,
    register: handleRegister,
    logout: handleLogout,
    clearError: handleClearError,
  };
};
