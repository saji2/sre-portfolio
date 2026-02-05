package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/sre-portfolio/api/internal/model"
)

var ErrTaskNotFound = errors.New("task not found")

type TaskRepository struct {
	db *sql.DB
}

func NewTaskRepository(db *sql.DB) *TaskRepository {
	return &TaskRepository{db: db}
}

func (r *TaskRepository) Create(ctx context.Context, task *model.Task) error {
	query := `
		INSERT INTO tasks (user_id, title, description, status, priority, due_date, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())
		RETURNING id, created_at, updated_at
	`

	if task.Status == "" {
		task.Status = model.StatusTodo
	}
	if task.Priority == "" {
		task.Priority = model.PriorityMedium
	}

	err := r.db.QueryRowContext(ctx, query,
		task.UserID,
		task.Title,
		task.Description,
		task.Status,
		task.Priority,
		task.DueDate,
	).Scan(&task.ID, &task.CreatedAt, &task.UpdatedAt)

	return err
}

func (r *TaskRepository) GetByID(ctx context.Context, id, userID int64) (*model.Task, error) {
	query := `
		SELECT id, user_id, title, description, status, priority, due_date, created_at, updated_at
		FROM tasks
		WHERE id = $1 AND user_id = $2
	`

	task := &model.Task{}
	err := r.db.QueryRowContext(ctx, query, id, userID).Scan(
		&task.ID,
		&task.UserID,
		&task.Title,
		&task.Description,
		&task.Status,
		&task.Priority,
		&task.DueDate,
		&task.CreatedAt,
		&task.UpdatedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrTaskNotFound
	}
	if err != nil {
		return nil, err
	}

	return task, nil
}

func (r *TaskRepository) List(ctx context.Context, userID int64, filter model.TaskFilter) ([]model.Task, int, error) {
	countQuery := `SELECT COUNT(*) FROM tasks WHERE user_id = $1`
	args := []interface{}{userID}
	argIndex := 2

	if filter.Status != "" {
		countQuery += fmt.Sprintf(` AND status = $%d`, argIndex)
		args = append(args, filter.Status)
		argIndex++
	}
	if filter.Priority != "" {
		countQuery += fmt.Sprintf(` AND priority = $%d`, argIndex)
		args = append(args, filter.Priority)
		argIndex++
	}

	var total int
	err := r.db.QueryRowContext(ctx, countQuery, args...).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	if filter.Page <= 0 {
		filter.Page = 1
	}
	if filter.PerPage <= 0 {
		filter.PerPage = 20
	}

	offset := (filter.Page - 1) * filter.PerPage

	query := `
		SELECT id, user_id, title, description, status, priority, due_date, created_at, updated_at
		FROM tasks
		WHERE user_id = $1
	`
	queryArgs := []interface{}{userID}
	queryArgIndex := 2

	if filter.Status != "" {
		query += fmt.Sprintf(` AND status = $%d`, queryArgIndex)
		queryArgs = append(queryArgs, filter.Status)
		queryArgIndex++
	}
	if filter.Priority != "" {
		query += fmt.Sprintf(` AND priority = $%d`, queryArgIndex)
		queryArgs = append(queryArgs, filter.Priority)
		queryArgIndex++
	}

	query += fmt.Sprintf(` ORDER BY created_at DESC LIMIT $%d OFFSET $%d`, queryArgIndex, queryArgIndex+1)
	queryArgs = append(queryArgs, filter.PerPage, offset)

	rows, err := r.db.QueryContext(ctx, query, queryArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var tasks []model.Task
	for rows.Next() {
		var task model.Task
		err := rows.Scan(
			&task.ID,
			&task.UserID,
			&task.Title,
			&task.Description,
			&task.Status,
			&task.Priority,
			&task.DueDate,
			&task.CreatedAt,
			&task.UpdatedAt,
		)
		if err != nil {
			return nil, 0, err
		}
		tasks = append(tasks, task)
	}

	if err := rows.Err(); err != nil {
		return nil, 0, err
	}

	if tasks == nil {
		tasks = []model.Task{}
	}

	return tasks, total, nil
}

func (r *TaskRepository) Update(ctx context.Context, task *model.Task) error {
	query := `
		UPDATE tasks
		SET title = $1, description = $2, status = $3, priority = $4, due_date = $5, updated_at = NOW()
		WHERE id = $6 AND user_id = $7
		RETURNING updated_at
	`

	err := r.db.QueryRowContext(ctx, query,
		task.Title,
		task.Description,
		task.Status,
		task.Priority,
		task.DueDate,
		task.ID,
		task.UserID,
	).Scan(&task.UpdatedAt)

	if errors.Is(err, sql.ErrNoRows) {
		return ErrTaskNotFound
	}
	return err
}

func (r *TaskRepository) UpdateStatus(ctx context.Context, id, userID int64, status model.TaskStatus) error {
	query := `
		UPDATE tasks
		SET status = $1, updated_at = NOW()
		WHERE id = $2 AND user_id = $3
	`

	result, err := r.db.ExecContext(ctx, query, status, id, userID)
	if err != nil {
		return err
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if rowsAffected == 0 {
		return ErrTaskNotFound
	}

	return nil
}

func (r *TaskRepository) Delete(ctx context.Context, id, userID int64) error {
	query := `DELETE FROM tasks WHERE id = $1 AND user_id = $2`

	result, err := r.db.ExecContext(ctx, query, id, userID)
	if err != nil {
		return err
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if rowsAffected == 0 {
		return ErrTaskNotFound
	}

	return nil
}
