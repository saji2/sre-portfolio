import { useCallback } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import type { RootState, AppDispatch } from '../store';
import {
  fetchTasks,
  createTask,
  updateTask,
  updateTaskStatus,
  deleteTask,
  clearError,
} from '../store/taskSlice';
import type { CreateTaskData, UpdateTaskData, TaskStatus } from '../types';
import { TaskFilterParams } from '../services/tasks';

export const useTasks = () => {
  const dispatch = useDispatch<AppDispatch>();
  const { tasks, total, page, perPage, loading, error } = useSelector(
    (state: RootState) => state.tasks
  );

  const handleFetchTasks = useCallback(
    (params?: TaskFilterParams) => {
      return dispatch(fetchTasks(params));
    },
    [dispatch]
  );

  const handleCreateTask = useCallback(
    (data: CreateTaskData) => {
      return dispatch(createTask(data));
    },
    [dispatch]
  );

  const handleUpdateTask = useCallback(
    (id: number, data: UpdateTaskData) => {
      return dispatch(updateTask({ id, data }));
    },
    [dispatch]
  );

  const handleUpdateTaskStatus = useCallback(
    (id: number, status: TaskStatus) => {
      return dispatch(updateTaskStatus({ id, status }));
    },
    [dispatch]
  );

  const handleDeleteTask = useCallback(
    (id: number) => {
      return dispatch(deleteTask(id));
    },
    [dispatch]
  );

  const handleClearError = useCallback(() => {
    dispatch(clearError());
  }, [dispatch]);

  return {
    tasks,
    total,
    page,
    perPage,
    loading,
    error,
    fetchTasks: handleFetchTasks,
    createTask: handleCreateTask,
    updateTask: handleUpdateTask,
    updateTaskStatus: handleUpdateTaskStatus,
    deleteTask: handleDeleteTask,
    clearError: handleClearError,
  };
};
