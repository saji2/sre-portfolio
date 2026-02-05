package handler

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/sre-portfolio/api/internal/middleware"
	"github.com/sre-portfolio/api/internal/model"
	"github.com/sre-portfolio/api/internal/service"
)

type TaskHandler struct {
	taskService *service.TaskService
}

func NewTaskHandler(taskService *service.TaskService) *TaskHandler {
	return &TaskHandler{
		taskService: taskService,
	}
}

func (h *TaskHandler) Create(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req model.CreateTaskRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	task, err := h.taskService.Create(c.Request.Context(), userID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create task"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": task})
}

func (h *TaskHandler) Get(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	taskID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid task id"})
		return
	}

	task, err := h.taskService.GetByID(c.Request.Context(), taskID, userID)
	if err != nil {
		if errors.Is(err, service.ErrTaskNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "task not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get task"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": task})
}

func (h *TaskHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	filter := model.TaskFilter{
		Status:   model.TaskStatus(c.Query("status")),
		Priority: model.TaskPriority(c.Query("priority")),
		Page:     1,
		PerPage:  20,
	}

	if page, err := strconv.Atoi(c.Query("page")); err == nil && page > 0 {
		filter.Page = page
	}
	if perPage, err := strconv.Atoi(c.Query("per_page")); err == nil && perPage > 0 && perPage <= 100 {
		filter.PerPage = perPage
	}

	response, err := h.taskService.List(c.Request.Context(), userID, filter)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list tasks"})
		return
	}

	c.JSON(http.StatusOK, response)
}

func (h *TaskHandler) Update(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	taskID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid task id"})
		return
	}

	var req model.UpdateTaskRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	task, err := h.taskService.Update(c.Request.Context(), taskID, userID, req)
	if err != nil {
		if errors.Is(err, service.ErrTaskNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "task not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update task"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": task})
}

func (h *TaskHandler) UpdateStatus(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	taskID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid task id"})
		return
	}

	var req model.UpdateStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.taskService.UpdateStatus(c.Request.Context(), taskID, userID, req.Status); err != nil {
		if errors.Is(err, service.ErrTaskNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "task not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update task status"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "status updated successfully"})
}

func (h *TaskHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	taskID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid task id"})
		return
	}

	if err := h.taskService.Delete(c.Request.Context(), taskID, userID); err != nil {
		if errors.Is(err, service.ErrTaskNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "task not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete task"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "task deleted successfully"})
}
