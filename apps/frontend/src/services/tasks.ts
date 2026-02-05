import api from './api';
import type { Task, TaskListResponse, CreateTaskData, UpdateTaskData, TaskStatus } from '../types';

export interface TaskFilterParams {
  status?: TaskStatus;
  priority?: string;
  page?: number;
  per_page?: number;
}

export const taskService = {
  async list(params?: TaskFilterParams): Promise<TaskListResponse> {
    const response = await api.get<TaskListResponse>('/v1/tasks', { params });
    return response.data;
  },

  async get(id: number): Promise<{ data: Task }> {
    const response = await api.get<{ data: Task }>(`/v1/tasks/${id}`);
    return response.data;
  },

  async create(data: CreateTaskData): Promise<{ data: Task }> {
    const response = await api.post<{ data: Task }>('/v1/tasks', data);
    return response.data;
  },

  async update(id: number, data: UpdateTaskData): Promise<{ data: Task }> {
    const response = await api.put<{ data: Task }>(`/v1/tasks/${id}`, data);
    return response.data;
  },

  async updateStatus(id: number, status: TaskStatus): Promise<void> {
    await api.patch(`/v1/tasks/${id}/status`, { status });
  },

  async delete(id: number): Promise<void> {
    await api.delete(`/v1/tasks/${id}`);
  },
};
