import { useAuth } from '../hooks/useAuth';
import { TaskList } from '../components/tasks/TaskList';

export const DashboardPage = () => {
  const { logout } = useAuth();

  const handleLogout = async () => {
    try {
      await logout();
    } catch (err) {
      console.error('Logout failed:', err);
    }
  };

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white shadow">
        <div className="max-w-7xl mx-auto px-4 py-4 sm:px-6 lg:px-8 flex justify-between items-center">
          <h1 className="text-2xl font-bold text-gray-900">Task Manager</h1>
          <button
            type="button"
            onClick={handleLogout}
            aria-label="Logout"
            className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200"
          >
            Logout
          </button>
        </div>
      </header>
      <main className="max-w-7xl mx-auto px-4 py-8 sm:px-6 lg:px-8">
        <TaskList />
      </main>
    </div>
  );
};
