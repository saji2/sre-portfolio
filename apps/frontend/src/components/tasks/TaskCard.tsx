import type { Task, TaskStatus, TaskPriority } from '../../types';
import { useTasks } from '../../hooks/useTasks';

interface TaskCardProps {
  task: Task;
  onEdit: (task: Task) => void;
}

const statusColors: Record<TaskStatus, string> = {
  TODO: 'bg-gray-100 text-gray-800',
  IN_PROGRESS: 'bg-blue-100 text-blue-800',
  DONE: 'bg-green-100 text-green-800',
};

const priorityColors: Record<TaskPriority, string> = {
  LOW: 'bg-gray-200 text-gray-600',
  MEDIUM: 'bg-yellow-100 text-yellow-800',
  HIGH: 'bg-red-100 text-red-800',
};

export const TaskCard = ({ task, onEdit }: TaskCardProps) => {
  const { updateTaskStatus, deleteTask } = useTasks();

  const handleStatusChange = async (status: TaskStatus) => {
    try {
      await updateTaskStatus(task.id, status);
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to update status');
    }
  };

  const handleDelete = async () => {
    if (window.confirm('Are you sure you want to delete this task?')) {
      try {
        await deleteTask(task.id);
      } catch (err) {
        alert(err instanceof Error ? err.message : 'Failed to delete task');
      }
    }
  };

  return (
    <div className="bg-white rounded-lg shadow p-4 hover:shadow-md transition-shadow">
      <div className="flex justify-between items-start mb-2">
        <h3 className="text-lg font-medium text-gray-900">{task.title}</h3>
        <div className="flex gap-2">
          <span className={`px-2 py-1 text-xs rounded-full ${priorityColors[task.priority]}`}>
            {task.priority}
          </span>
          <span className={`px-2 py-1 text-xs rounded-full ${statusColors[task.status]}`}>
            {task.status.replace('_', ' ')}
          </span>
        </div>
      </div>

      {task.description && (
        <p className="text-gray-600 text-sm mb-3">{task.description}</p>
      )}

      {task.due_date && (
        <p className="text-gray-500 text-xs mb-3">
          Due: {new Date(task.due_date).toLocaleDateString()}
        </p>
      )}

      <div className="flex justify-between items-center pt-3 border-t">
        <div className="flex gap-2">
          <select
            value={task.status}
            onChange={(e) => handleStatusChange(e.target.value as TaskStatus)}
            aria-label="Task status"
            className="text-sm border rounded px-2 py-1"
          >
            <option value="TODO">Todo</option>
            <option value="IN_PROGRESS">In Progress</option>
            <option value="DONE">Done</option>
          </select>
        </div>
        <div className="flex gap-2">
          <button
            type="button"
            onClick={() => onEdit(task)}
            className="text-blue-600 hover:text-blue-800 text-sm"
          >
            Edit
          </button>
          <button
            type="button"
            onClick={handleDelete}
            className="text-red-600 hover:text-red-800 text-sm"
          >
            Delete
          </button>
        </div>
      </div>
    </div>
  );
};
