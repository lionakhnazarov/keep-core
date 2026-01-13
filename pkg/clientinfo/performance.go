package clientinfo

import (
	"runtime"
	"strings"
	"sync"
	"time"
)

// PerformanceMetricsRecorder provides a simple interface for recording
// performance metrics. It can be nil if metrics are not enabled.
type PerformanceMetricsRecorder interface {
	// IncrementCounter increments a counter metric
	IncrementCounter(name string, value float64)
	// RecordDuration records a duration in seconds
	RecordDuration(name string, duration time.Duration)
	// SetGauge sets a gauge metric value
	SetGauge(name string, value float64)
	// GetCounterValue returns current counter value
	GetCounterValue(name string) float64
	// GetGaugeValue returns current gauge value
	GetGaugeValue(name string) float64
}

// PerformanceMetrics provides a way to record performance-related metrics
// including operation counts, durations, and queue sizes.
// It implements PerformanceMetricsRecorder interface.
type PerformanceMetrics struct {
	registry *Registry

	// Counters track cumulative counts of events
	countersMutex sync.RWMutex
	counters      map[string]*counter

	// Histograms track distributions of values (like durations)
	histogramsMutex sync.RWMutex
	histograms      map[string]*histogram

	// Gauges track current values (like queue sizes)
	gaugesMutex sync.RWMutex
	gauges      map[string]*gauge
}

// Ensure PerformanceMetrics implements PerformanceMetricsRecorder
var _ PerformanceMetricsRecorder = (*PerformanceMetrics)(nil)

type counter struct {
	value float64
	mutex sync.RWMutex
}

type histogram struct {
	buckets map[float64]float64 // bucket upper bound -> count
	mutex   sync.RWMutex
}

type gauge struct {
	value float64
	mutex sync.RWMutex
}

// NewPerformanceMetrics creates a new performance metrics instance.
func NewPerformanceMetrics(registry *Registry) *PerformanceMetrics {
	pm := &PerformanceMetrics{
		registry:   registry,
		counters:   make(map[string]*counter),
		histograms: make(map[string]*histogram),
		gauges:     make(map[string]*gauge),
	}

	// Register all metrics upfront with 0 values so they appear in /metrics endpoint
	pm.registerAllMetrics()

	// Register gauge observers for all gauges
	go pm.observeGauges()

	// Start observing system metrics
	go pm.observeSystemMetrics()

	return pm
}

// registerAllMetrics registers all performance metrics with 0 values
// so they appear in the /metrics endpoint even before operations occur.
func (pm *PerformanceMetrics) registerAllMetrics() {
	// Register all counter metrics with 0 initial value
	counters := []string{
		MetricDKGJoinedTotal,
		MetricDKGFailedTotal,
		MetricDKGValidationTotal,
		MetricDKGChallengesSubmittedTotal,
		MetricDKGApprovalsSubmittedTotal,
		MetricSigningOperationsTotal,
		MetricSigningSuccessTotal,
		MetricSigningFailedTotal,
		MetricSigningTimeoutsTotal,
		MetricWalletActionsTotal,
		MetricWalletActionSuccessTotal,
		MetricWalletActionFailedTotal,
		MetricWalletHeartbeatFailuresTotal,
		MetricCoordinationWindowsDetectedTotal,
		MetricCoordinationProceduresExecutedTotal,
		MetricCoordinationFailedTotal,
		MetricPeerConnectionsTotal,
		MetricPeerDisconnectionsTotal,
		MetricMessageBroadcastTotal,
		MetricMessageReceivedTotal,
		MetricPingTestsTotal,
		MetricPingTestSuccessTotal,
		MetricPingTestFailedTotal,
		MetricWalletDispatcherRejectedTotal,
	}

	// First, initialize all counters in the map
	for _, name := range counters {
		pm.counters[name] = &counter{value: 0}
	}

	// Then, register observers (this prevents concurrent map read/write)
	for _, name := range counters {
		metricName := name // Capture for closure
		pm.registry.ObserveApplicationSource(
			"performance",
			map[string]Source{
				metricName: func() float64 {
					pm.countersMutex.RLock()
					c, exists := pm.counters[metricName]
					pm.countersMutex.RUnlock()
					if !exists {
						return 0
					}
					c.mutex.RLock()
					defer c.mutex.RUnlock()
					return c.value
				},
			},
		)
	}

	// Register all duration/histogram metrics with 0 initial values
	// Note: These use the actual metric names as used in the codebase
	durationMetrics := []string{
		"dkg_duration_seconds",
		"signing_duration_seconds",
		"wallet_action_duration_seconds",
		"coordination_duration_seconds",
		"ping_test_duration_seconds",
	}

	// First, initialize all histograms in the map
	for _, name := range durationMetrics {
		pm.histograms[name] = &histogram{
			buckets: make(map[float64]float64),
		}
	}

	// Then, register observers (this prevents concurrent map read/write)
	for _, name := range durationMetrics {
		metricName := name
		pm.registry.ObserveApplicationSource(
			"performance",
			map[string]Source{
				metricName: func() float64 {
					pm.histogramsMutex.RLock()
					h, exists := pm.histograms[metricName]
					pm.histogramsMutex.RUnlock()
					if !exists {
						return 0
					}
					h.mutex.RLock()
					defer h.mutex.RUnlock()
					count := h.buckets[-1]
					if count == 0 {
						return 0
					}
					return h.buckets[-2] / count // average
				},
				metricName + "_count": func() float64 {
					pm.histogramsMutex.RLock()
					h, exists := pm.histograms[metricName]
					pm.histogramsMutex.RUnlock()
					if !exists {
						return 0
					}
					h.mutex.RLock()
					defer h.mutex.RUnlock()
					return h.buckets[-1]
				},
			},
		)
	}

	// Register all gauge metrics with 0 initial value
	gauges := []string{
		MetricWalletDispatcherActiveActions,
		MetricIncomingMessageQueueSize,
		MetricMessageHandlerQueueSize,
		MetricSigningAttemptsPerOperation,
		MetricCPUUtilization,
		MetricMemoryUsageMB,
		MetricGoroutineCount,
	}

	// First, initialize all gauges in the map
	for _, name := range gauges {
		pm.gauges[name] = &gauge{value: 0}
	}

	// Then, register observers (this prevents concurrent map read/write)
	for _, name := range gauges {
		metricName := name // Capture for closure
		pm.registry.ObserveApplicationSource(
			"performance",
			map[string]Source{
				metricName: func() float64 {
					pm.gaugesMutex.RLock()
					g, exists := pm.gauges[metricName]
					pm.gaugesMutex.RUnlock()
					if !exists {
						return 0
					}
					g.mutex.RLock()
					defer g.mutex.RUnlock()
					return g.value
				},
			},
		)
	}

}

// IncrementCounter increments a counter metric by the given value.
func (pm *PerformanceMetrics) IncrementCounter(name string, value float64) {
	pm.countersMutex.Lock()
	c, exists := pm.counters[name]
	if !exists {
		c = &counter{value: 0}
		pm.counters[name] = c
	}
	pm.countersMutex.Unlock()

	c.mutex.Lock()
	c.value += value
	c.mutex.Unlock()

	// Update the gauge observer for this counter
	pm.registry.ObserveApplicationSource(
		"performance",
		map[string]Source{
			name: func() float64 {
				c.mutex.RLock()
				defer c.mutex.RUnlock()
				return c.value
			},
		},
	)
}

// RecordDuration records a duration value in a histogram.
// The duration is recorded in seconds.
func (pm *PerformanceMetrics) RecordDuration(name string, duration time.Duration) {
	pm.histogramsMutex.Lock()
	h, exists := pm.histograms[name]
	if !exists {
		h = &histogram{
			buckets: make(map[float64]float64),
		}
		pm.histograms[name] = h
	}
	pm.histogramsMutex.Unlock()

	seconds := duration.Seconds()
	h.mutex.Lock()
	// Simple histogram: increment bucket counts
	// Buckets: 0.001, 0.01, 0.1, 1, 10, 60, 300, 600
	buckets := []float64{0.001, 0.01, 0.1, 1, 10, 60, 300, 600}
	for _, bucket := range buckets {
		if seconds <= bucket {
			h.buckets[bucket]++
			break
		}
	}
	// Also track total count and sum for average calculation
	h.buckets[-1]++          // -1 = count
	h.buckets[-2] += seconds // -2 = sum
	h.mutex.Unlock()

	metricName := name
	if !strings.HasSuffix(name, "_duration_seconds") {
		metricName = name + "_duration_seconds"
	}

	// Expose as gauge for now (Prometheus-style histograms would be better)
	pm.registry.ObserveApplicationSource(
		"performance",
		map[string]Source{
			metricName: func() float64 {
				h.mutex.RLock()
				defer h.mutex.RUnlock()
				count := h.buckets[-1]
				if count == 0 {
					return 0
				}
				return h.buckets[-2] / count // average
			},
			metricName + "_count": func() float64 {
				h.mutex.RLock()
				defer h.mutex.RUnlock()
				return h.buckets[-1]
			},
		},
	)
}

// SetGauge sets a gauge metric to the given value.
func (pm *PerformanceMetrics) SetGauge(name string, value float64) {
	pm.gaugesMutex.Lock()
	g, exists := pm.gauges[name]
	if !exists {
		g = &gauge{value: 0}
		pm.gauges[name] = g
	}
	pm.gaugesMutex.Unlock()

	g.mutex.Lock()
	g.value = value
	g.mutex.Unlock()

	// Register gauge observer if not already registered
	pm.registry.ObserveApplicationSource(
		"performance",
		map[string]Source{
			name: func() float64 {
				g.mutex.RLock()
				defer g.mutex.RUnlock()
				return g.value
			},
		},
	)
}

// observeGauges periodically updates gauge observers.
// This is handled automatically by ObserveApplicationSource.
func (pm *PerformanceMetrics) observeGauges() {
	// Gauges are observed automatically via ObserveApplicationSource
	// This function is kept for future use if needed
}

// observeSystemMetrics periodically collects and updates system metrics
// including CPU utilization, memory usage, and goroutine count.
func (pm *PerformanceMetrics) observeSystemMetrics() {
	ticker := time.NewTicker(10 * time.Second) // Update every 10 seconds
	defer ticker.Stop()

	var lastMemStats runtime.MemStats
	var lastUpdateTime time.Time
	runtime.ReadMemStats(&lastMemStats)
	lastUpdateTime = time.Now()

	for range ticker.C {
		// Update goroutine count
		goroutineCount := float64(runtime.NumGoroutine())
		pm.SetGauge(MetricGoroutineCount, goroutineCount)

		// Update memory usage
		// Using Sys (total memory obtained from OS) for accurate total memory footprint
		// This includes heap, stack, GC metadata, and other runtime overhead
		// For heap-only memory, use memStats.Alloc instead
		var memStats runtime.MemStats
		runtime.ReadMemStats(&memStats)
		memoryUsageMB := float64(memStats.Sys) / (1024 * 1024) // Total memory in megabytes
		pm.SetGauge(MetricMemoryUsageMB, memoryUsageMB)

		// Calculate CPU utilization using a more realistic heuristic
		now := time.Now()
		elapsed := now.Sub(lastUpdateTime)
		if elapsed > 0 {
			cpuUtilization := pm.calculateCPUUtilizationHeuristic(memStats, lastMemStats, elapsed)
			pm.SetGauge(MetricCPUUtilization, cpuUtilization)

			lastMemStats = memStats
			lastUpdateTime = now
		}
	}
}

// calculateCPUUtilizationHeuristic calculates CPU utilization using a heuristic
// based on goroutine count and GC activity. This provides a reasonable approximation.
// Note: For accurate CPU metrics, consider using OS-level process CPU time.
func (pm *PerformanceMetrics) calculateCPUUtilizationHeuristic(
	currentMemStats runtime.MemStats,
	lastMemStats runtime.MemStats,
	elapsed time.Duration,
) float64 {
	numCPU := float64(runtime.NumCPU())
	activeGoroutines := float64(runtime.NumGoroutine())

	// Calculate GC rate (GCs per second)
	gcDelta := float64(currentMemStats.NumGC - lastMemStats.NumGC)
	gcRate := gcDelta / elapsed.Seconds()

	// Normalize goroutines: if we have more goroutines than CPU cores,
	// we're likely using more CPU, but use a conservative multiplier
	// Formula: (goroutines / CPU cores) * 10%, capped at 40%
	goroutineContribution := (activeGoroutines / numCPU) * 10.0
	if goroutineContribution > 40.0 {
		goroutineContribution = 40.0
	}

	// GC contribution: frequent GCs indicate CPU work, but use conservative multiplier
	// Formula: GC rate * 1%, capped at 20%
	gcContribution := gcRate * 1.0
	if gcContribution > 20.0 {
		gcContribution = 20.0
	}

	// Total CPU utilization estimate
	cpuUtilization := goroutineContribution + gcContribution

	// Add a small base load if there are active goroutines
	if cpuUtilization < 1.0 && activeGoroutines > 0 {
		cpuUtilization = 1.0 // Minimum 1% if there are active goroutines
	}

	// Cap CPU utilization at 100%
	if cpuUtilization > 100.0 {
		cpuUtilization = 100.0
	}
	if cpuUtilization < 0.0 {
		cpuUtilization = 0.0
	}

	return cpuUtilization
}

// NoOpPerformanceMetrics is a no-op implementation of PerformanceMetricsRecorder
// that can be used when metrics are disabled.
type NoOpPerformanceMetrics struct{}

// IncrementCounter is a no-op.
func (n *NoOpPerformanceMetrics) IncrementCounter(name string, value float64) {}

// RecordDuration is a no-op.
func (n *NoOpPerformanceMetrics) RecordDuration(name string, duration time.Duration) {}

// SetGauge is a no-op.
func (n *NoOpPerformanceMetrics) SetGauge(name string, value float64) {}

// GetCounterValue always returns 0.
func (n *NoOpPerformanceMetrics) GetCounterValue(name string) float64 { return 0 }

// GetGaugeValue always returns 0.
func (n *NoOpPerformanceMetrics) GetGaugeValue(name string) float64 { return 0 }

// GetCounterValue returns the current value of a counter.
func (pm *PerformanceMetrics) GetCounterValue(name string) float64 {
	pm.countersMutex.RLock()
	c, exists := pm.counters[name]
	pm.countersMutex.RUnlock()

	if !exists {
		return 0
	}

	c.mutex.RLock()
	defer c.mutex.RUnlock()
	return c.value
}

// GetGaugeValue returns the current value of a gauge.
func (pm *PerformanceMetrics) GetGaugeValue(name string) float64 {
	pm.gaugesMutex.RLock()
	g, exists := pm.gauges[name]
	pm.gaugesMutex.RUnlock()

	if !exists {
		return 0
	}

	g.mutex.RLock()
	defer g.mutex.RUnlock()
	return g.value
}

// Metric names for performance metrics
const (
	// DKG Metrics
	MetricDKGJoinedTotal              = "dkg_joined_total"
	MetricDKGFailedTotal              = "dkg_failed_total"
	MetricDKGDurationSeconds          = "dkg_duration_seconds"
	MetricDKGValidationTotal          = "dkg_validation_total"
	MetricDKGChallengesSubmittedTotal = "dkg_challenges_submitted_total"
	MetricDKGApprovalsSubmittedTotal  = "dkg_approvals_submitted_total"

	// Signing Metrics
	MetricSigningOperationsTotal      = "signing_operations_total"
	MetricSigningSuccessTotal         = "signing_success_total"
	MetricSigningFailedTotal          = "signing_failed_total"
	MetricSigningDurationSeconds      = "signing_duration_seconds"
	MetricSigningAttemptsPerOperation = "signing_attempts_per_operation"
	MetricSigningTimeoutsTotal        = "signing_timeouts_total"

	// Wallet Action Metrics
	MetricWalletActionsTotal           = "wallet_actions_total"
	MetricWalletActionSuccessTotal     = "wallet_action_success_total"
	MetricWalletActionFailedTotal      = "wallet_action_failed_total"
	MetricWalletActionDurationSeconds  = "wallet_action_duration_seconds"
	MetricWalletHeartbeatFailuresTotal = "wallet_heartbeat_failures_total"

	// Coordination Metrics
	MetricCoordinationWindowsDetectedTotal    = "coordination_windows_detected_total"
	MetricCoordinationProceduresExecutedTotal = "coordination_procedures_executed_total"
	MetricCoordinationFailedTotal             = "coordination_failed_total"
	MetricCoordinationDurationSeconds         = "coordination_duration_seconds"

	// Network Metrics
	MetricIncomingMessageQueueSize = "incoming_message_queue_size"
	MetricMessageHandlerQueueSize  = "message_handler_queue_size"
	MetricPeerConnectionsTotal     = "peer_connections_total"
	MetricPeerDisconnectionsTotal  = "peer_disconnections_total"
	MetricMessageBroadcastTotal    = "message_broadcast_total"
	MetricMessageReceivedTotal     = "message_received_total"
	MetricPingTestsTotal           = "ping_test_total"
	MetricPingTestSuccessTotal     = "ping_test_success_total"
	MetricPingTestFailedTotal      = "ping_test_failed_total"

	// Wallet Dispatcher Metrics
	MetricWalletDispatcherActiveActions = "wallet_dispatcher_active_actions"
	MetricWalletDispatcherRejectedTotal = "wallet_dispatcher_rejected_total"

	// System Metrics
	MetricCPUUtilization = "cpu_utilization_percent"
	MetricMemoryUsageMB  = "memory_usage_mb"
	MetricGoroutineCount = "goroutine_count"
)
