import { createSlice, createAsyncThunk, PayloadAction } from '@reduxjs/toolkit';
import { taskService, TaskFilterParams } from '../services/tasks';
import type { Task, CreateTaskData, UpdateTaskData, TaskStatus } from '../types';

interface TaskState {
  tasks: Task[];
  total: number;
  page: number;
  perPage: number;
  loading: boolean;
  error: string | null;
}

const initialState: TaskState = {
  tasks: [],
  total: 0,
  page: 1,
  perPage: 20,
  loading: false,
  error: null,
};

export const fetchTasks = createAsyncThunk(
  'tasks/fetchTasks',
  async (params?: TaskFilterParams) => {
    const response = await taskService.list(params);
    return response;
  }
);

export const createTask = createAsyncThunk(
  'tasks/createTask',
  async (data: CreateTaskData) => {
    const response = await taskService.create(data);
    return response.data;
  }
);

export const updateTask = createAsyncThunk(
  'tasks/updateTask',
  async ({ id, data }: { id: number; data: UpdateTaskData }) => {
    const response = await taskService.update(id, data);
    return response.data;
  }
);

export const updateTaskStatus = createAsyncThunk(
  'tasks/updateTaskStatus',
  async ({ id, status }: { id: number; status: TaskStatus }) => {
    await taskService.updateStatus(id, status);
    return { id, status };
  }
);

export const deleteTask = createAsyncThunk(
  'tasks/deleteTask',
  async (id: number) => {
    await taskService.delete(id);
    return id;
  }
);

const taskSlice = createSlice({
  name: 'tasks',
  initialState,
  reducers: {
    clearError: (state) => {
      state.error = null;
    },
  },
  extraReducers: (builder) => {
    builder
      .addCase(fetchTasks.pending, (state) => {
        state.loading = true;
        state.error = null;
      })
      .addCase(fetchTasks.fulfilled, (state, action) => {
        state.loading = false;
        state.tasks = action.payload.data;
        state.total = action.payload.meta.total;
        state.page = action.payload.meta.page;
        state.perPage = action.payload.meta.per_page;
      })
      .addCase(fetchTasks.rejected, (state, action) => {
        state.loading = false;
        state.error = action.error.message || 'Failed to fetch tasks';
      })
      .addCase(createTask.pending, (state) => {
        state.error = null;
      })
      .addCase(createTask.fulfilled, (state, action: PayloadAction<Task>) => {
        if (state.page === 1) {
          state.tasks.unshift(action.payload);
        }
        state.total += 1;
      })
      .addCase(createTask.rejected, (state, action) => {
        state.error = action.error.message || 'Failed to create task';
      })
      .addCase(updateTask.pending, (state) => {
        state.error = null;
      })
      .addCase(updateTask.fulfilled, (state, action: PayloadAction<Task>) => {
        const index = state.tasks.findIndex((t) => t.id === action.payload.id);
        if (index !== -1) {
          state.tasks[index] = action.payload;
        }
      })
      .addCase(updateTask.rejected, (state, action) => {
        state.error = action.error.message || 'Failed to update task';
      })
      .addCase(updateTaskStatus.pending, (state) => {
        state.error = null;
      })
      .addCase(updateTaskStatus.fulfilled, (state, action) => {
        const index = state.tasks.findIndex((t) => t.id === action.payload.id);
        if (index !== -1) {
          state.tasks[index].status = action.payload.status;
        }
      })
      .addCase(updateTaskStatus.rejected, (state, action) => {
        state.error = action.error.message || 'Failed to update task status';
      })
      .addCase(deleteTask.pending, (state) => {
        state.error = null;
      })
      .addCase(deleteTask.fulfilled, (state, action: PayloadAction<number>) => {
        state.tasks = state.tasks.filter((t) => t.id !== action.payload);
        state.total = Math.max(0, state.total - 1);
      })
      .addCase(deleteTask.rejected, (state, action) => {
        state.error = action.error.message || 'Failed to delete task';
      });
  },
});

export const { clearError } = taskSlice.actions;
export default taskSlice.reducer;
