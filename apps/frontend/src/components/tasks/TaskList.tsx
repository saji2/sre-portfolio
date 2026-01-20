import { useEffect, useRef, useState } from 'react';
import { useTasks } from '../../hooks/useTasks';
import { TaskCard } from './TaskCard';
import { TaskForm } from './TaskForm';
import type { Task, TaskStatus } from '../../types';

export const TaskList = () => {
  const { tasks, loading, error, fetchTasks, createTask, updateTask } = useTasks();
  const [showForm, setShowForm] = useState(false);
  const [editingTask, setEditingTask] = useState<Task | null>(null);
  const [statusFilter, setStatusFilter] = useState<TaskStatus | ''>('');
  const [formError, setFormError] = useState<string | null>(null);

  const fetchTasksRef = useRef(fetchTasks);
  fetchTasksRef.current = fetchTasks;

  useEffect(() => {
    fetchTasksRef.current(statusFilter ? { status: statusFilter } : undefined);
  }, [statusFilter]);

  const handleCreateOrUpdate = async (data: Parameters<typeof createTask>[0]) => {
    try {
      setFormError(null);
      if (editingTask) {
        await updateTask(editingTask.id, data);
      } else {
        await createTask(data);
      }
      setShowForm(false);
      setEditingTask(null);
    } catch (err) {
      setFormError(err instanceof Error ? err.message : 'Failed to save task');
    }
  };

  const handleEdit = (task: Task) => {
    setEditingTask(task);
    setShowForm(true);
  };

  const handleCancel = () => {
    setShowForm(false);
    setEditingTask(null);
  };

  if (loading && tasks.length === 0) {
    return (
      <div className="flex justify-center items-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
      </div>
    );
  }

  return (
    <div>
      <div className="flex justify-between items-center mb-6">
        <div className="flex items-center gap-4">
          <h2 className="text-xl font-bold">Tasks</h2>
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value as TaskStatus | '')}
            aria-label="Filter tasks by status"
            className="border rounded px-3 py-1 text-sm"
          >
            <option value="">All</option>
            <option value="TODO">Todo</option>
            <option value="IN_PROGRESS">In Progress</option>
            <option value="DONE">Done</option>
          </select>
        </div>
        <button
          type="button"
          onClick={() => setShowForm(true)}
          className="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700"
        >
          Add Task
        </button>
      </div>

      {(error || formError) && (
        <div role="alert" className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
          {error && <div>{error}</div>}
          {formError && error !== formError && <div>{formError}</div>}
        </div>
      )}

      {tasks.length === 0 ? (
        <div className="text-center py-12 text-gray-500">
          No tasks found. Create one to get started!
        </div>
      ) : (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {tasks.map((task) => (
            <TaskCard key={task.id} task={task} onEdit={handleEdit} />
          ))}
        </div>
      )}

      {showForm && (
        <TaskForm
          task={editingTask}
          onSubmit={handleCreateOrUpdate}
          onCancel={handleCancel}
        />
      )}
    </div>
  );
};
