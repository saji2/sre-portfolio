package model

import "time"

type TaskStatus string

const (
	StatusTodo       TaskStatus = "TODO"
	StatusInProgress TaskStatus = "IN_PROGRESS"
	StatusDone       TaskStatus = "DONE"
)

type TaskPriority string

const (
	PriorityLow    TaskPriority = "LOW"
	PriorityMedium TaskPriority = "MEDIUM"
	PriorityHigh   TaskPriority = "HIGH"
)

type Task struct {
	ID          int64        `json:"id"`
	UserID      int64        `json:"user_id"`
	Title       string       `json:"title"`
	Description string       `json:"description,omitempty"`
	Status      TaskStatus   `json:"status"`
	Priority    TaskPriority `json:"priority"`
	DueDate     *time.Time   `json:"due_date,omitempty"`
	CreatedAt   time.Time    `json:"created_at"`
	UpdatedAt   time.Time    `json:"updated_at"`
}

type CreateTaskRequest struct {
	Title       string       `json:"title" binding:"required,max=200"`
	Description string       `json:"description"`
	Status      TaskStatus   `json:"status" binding:"omitempty,oneof=TODO IN_PROGRESS DONE"`
	Priority    TaskPriority `json:"priority" binding:"omitempty,oneof=LOW MEDIUM HIGH"`
	DueDate     *time.Time   `json:"due_date"`
}

type UpdateTaskRequest struct {
	Title       string       `json:"title" binding:"max=200"`
	Description string       `json:"description"`
	Status      TaskStatus   `json:"status" binding:"omitempty,oneof=TODO IN_PROGRESS DONE"`
	Priority    TaskPriority `json:"priority" binding:"omitempty,oneof=LOW MEDIUM HIGH"`
	DueDate     *time.Time   `json:"due_date"`
}

type UpdateStatusRequest struct {
	Status TaskStatus `json:"status" binding:"required,oneof=TODO IN_PROGRESS DONE"`
}

type TaskListResponse struct {
	Data []Task   `json:"data"`
	Meta ListMeta `json:"meta"`
}

type ListMeta struct {
	Total   int `json:"total"`
	Page    int `json:"page"`
	PerPage int `json:"per_page"`
}

type TaskFilter struct {
	Status   TaskStatus
	Priority TaskPriority
	Page     int
	PerPage  int
}
