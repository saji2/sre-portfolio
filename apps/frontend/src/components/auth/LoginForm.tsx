import { useState, FormEvent } from 'react';
import { useAuth } from '../../hooks/useAuth';

export const LoginForm = () => {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [formError, setFormError] = useState<string | null>(null);
  const { login, loading, error } = useAuth();

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    try {
      setFormError(null);
      await login({ username: username.trim(), password });
    } catch (err) {
      setFormError(err instanceof Error ? err.message : 'Login failed');
    }
  };

  const displayError = error || formError;

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      {displayError && (
        <div role="alert" className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">
          {displayError}
        </div>
      )}
      <div>
        <label htmlFor="username" className="block text-sm font-medium text-gray-700">
          Username
        </label>
        <input
          id="username"
          name="username"
          type="text"
          autoComplete="username"
          value={username}
          onChange={(e) => setUsername(e.target.value)}
          required
          className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
        />
      </div>
      <div>
        <label htmlFor="password" className="block text-sm font-medium text-gray-700">
          Password
        </label>
        <input
          id="password"
          name="password"
          type="password"
          autoComplete="current-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
          className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
        />
      </div>
      <button
        type="submit"
        disabled={loading}
        className="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50"
      >
        {loading ? 'Signing in...' : 'Sign in'}
      </button>
    </form>
  );
};
