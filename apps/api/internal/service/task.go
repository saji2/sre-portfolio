package service

import (
	"context"
	"errors"

	"github.com/sre-portfolio/api/internal/model"
	"github.com/sre-portfolio/api/internal/repository"
)

var ErrTaskNotFound = errors.New("task not found")

type TaskService struct {
	taskRepo *repository.TaskRepository
}

func NewTaskService(taskRepo *repository.TaskRepository) *TaskService {
	return &TaskService{
		taskRepo: taskRepo,
	}
}

func (s *TaskService) Create(ctx context.Context, userID int64, req model.CreateTaskRequest) (*model.Task, error) {
	task := &model.Task{
		UserID:      userID,
		Title:       req.Title,
		Description: req.Description,
		Status:      req.Status,
		Priority:    req.Priority,
		DueDate:     req.DueDate,
	}

	if task.Status == "" {
		task.Status = model.StatusTodo
	}
	if task.Priority == "" {
		task.Priority = model.PriorityMedium
	}

	if err := s.taskRepo.Create(ctx, task); err != nil {
		return nil, err
	}

	return task, nil
}

func (s *TaskService) GetByID(ctx context.Context, id, userID int64) (*model.Task, error) {
	task, err := s.taskRepo.GetByID(ctx, id, userID)
	if err != nil {
		if errors.Is(err, repository.ErrTaskNotFound) {
			return nil, ErrTaskNotFound
		}
		return nil, err
	}
	return task, nil
}

func (s *TaskService) List(ctx context.Context, userID int64, filter model.TaskFilter) (*model.TaskListResponse, error) {
	tasks, total, err := s.taskRepo.List(ctx, userID, filter)
	if err != nil {
		return nil, err
	}

	return &model.TaskListResponse{
		Data: tasks,
		Meta: model.ListMeta{
			Total:   total,
			Page:    filter.Page,
			PerPage: filter.PerPage,
		},
	}, nil
}

func (s *TaskService) Update(ctx context.Context, id, userID int64, req model.UpdateTaskRequest) (*model.Task, error) {
	task, err := s.taskRepo.GetByID(ctx, id, userID)
	if err != nil {
		if errors.Is(err, repository.ErrTaskNotFound) {
			return nil, ErrTaskNotFound
		}
		return nil, err
	}

	if req.Title != "" {
		task.Title = req.Title
	}
	if req.Description != "" {
		task.Description = req.Description
	}
	if req.Status != "" {
		task.Status = req.Status
	}
	if req.Priority != "" {
		task.Priority = req.Priority
	}
	if req.DueDate != nil {
		task.DueDate = req.DueDate
	}

	if err := s.taskRepo.Update(ctx, task); err != nil {
		if errors.Is(err, repository.ErrTaskNotFound) {
			return nil, ErrTaskNotFound
		}
		return nil, err
	}

	return task, nil
}

func (s *TaskService) UpdateStatus(ctx context.Context, id, userID int64, status model.TaskStatus) error {
	if err := s.taskRepo.UpdateStatus(ctx, id, userID, status); err != nil {
		if errors.Is(err, repository.ErrTaskNotFound) {
			return ErrTaskNotFound
		}
		return err
	}
	return nil
}

func (s *TaskService) Delete(ctx context.Context, id, userID int64) error {
	if err := s.taskRepo.Delete(ctx, id, userID); err != nil {
		if errors.Is(err, repository.ErrTaskNotFound) {
			return ErrTaskNotFound
		}
		return err
	}
	return nil
}
