package tbtc

import (
	"fmt"
	"sync"
	"time"

	"github.com/keep-network/keep-core/pkg/chain"
	"github.com/keep-network/keep-core/pkg/clientinfo"
)

// coordinationWindowMetrics tracks detailed metrics for individual coordination windows.
type coordinationWindowMetrics struct {
	mu sync.RWMutex

	// windows stores metrics for each coordination window by window index
	windows map[uint64]*windowMetrics

	// performanceMetrics is used to record aggregate metrics
	performanceMetrics clientinfo.PerformanceMetricsRecorder

	// maxWindowsToTrack limits the number of windows to keep in memory
	// to prevent unbounded memory growth
	maxWindowsToTrack uint64
}

// windowMetrics contains all metrics for a single coordination window.
type windowMetrics struct {
	// Window identification
	WindowIndex       uint64
	CoordinationBlock uint64

	// Window timing
	StartTime    time.Time
	EndTime      time.Time
	Duration     time.Duration
	ActivePhaseEndBlock uint64
	EndBlock     uint64

	// Coordination statistics
	WalletsCoordinated     uint64
	WalletsSuccessful      uint64
	WalletsFailed          uint64
	TotalProceduresStarted uint64
	TotalProceduresCompleted uint64

	// Leader information
	Leaders map[string]uint64 // leader address -> count of wallets they led

	// Action type statistics
	ActionTypes map[string]uint64 // action type -> count

	// Fault statistics
	TotalFaults        uint64
	FaultsByType       map[string]uint64 // fault type -> count
	FaultsByCulprit    map[string]uint64 // culprit address -> count

	// Per-wallet coordination details
	WalletCoordinationDetails []walletCoordinationDetail
}

// walletCoordinationDetail contains metrics for a single wallet's coordination
// in a window.
type walletCoordinationDetail struct {
	WalletPublicKeyHash string
	Leader              string
	ActionType          string
	Success             bool
	Duration            time.Duration
	Faults              []string // fault types observed
	FaultCulprits       []string // addresses of fault culprits
}

// newCoordinationWindowMetrics creates a new coordination window metrics tracker.
func newCoordinationWindowMetrics(
	performanceMetrics clientinfo.PerformanceMetricsRecorder,
	maxWindowsToTrack uint64,
) *coordinationWindowMetrics {
	return &coordinationWindowMetrics{
		windows:            make(map[uint64]*windowMetrics),
		performanceMetrics: performanceMetrics,
		maxWindowsToTrack:  maxWindowsToTrack,
	}
}

// recordWindowStart records the start of a coordination window.
func (cwm *coordinationWindowMetrics) recordWindowStart(window *coordinationWindow) {
	cwm.mu.Lock()
	defer cwm.mu.Unlock()

	windowIndex := window.index()
	if windowIndex == 0 {
		// Invalid window, skip
		return
	}

	// Initialize window metrics if not exists
	if _, exists := cwm.windows[windowIndex]; !exists {
		cwm.windows[windowIndex] = &windowMetrics{
			WindowIndex:         windowIndex,
			CoordinationBlock:   window.coordinationBlock,
			StartTime:           time.Now(),
			ActivePhaseEndBlock: window.activePhaseEndBlock(),
			EndBlock:            window.endBlock(),
			Leaders:             make(map[string]uint64),
			ActionTypes:         make(map[string]uint64),
			FaultsByType:        make(map[string]uint64),
			FaultsByCulprit:      make(map[string]uint64),
			WalletCoordinationDetails: make([]walletCoordinationDetail, 0),
		}
	}

	// Clean up old windows if we exceed the limit
	cwm.cleanupOldWindows()
}

// recordWindowEnd records the end of a coordination window.
func (cwm *coordinationWindowMetrics) recordWindowEnd(window *coordinationWindow) {
	cwm.mu.Lock()
	defer cwm.mu.Unlock()

	windowIndex := window.index()
	if windowIndex == 0 {
		return
	}

	wm, exists := cwm.windows[windowIndex]
	if !exists {
		return
	}

	wm.EndTime = time.Now()
	wm.Duration = wm.EndTime.Sub(wm.StartTime)

	// Record aggregate metrics
	if cwm.performanceMetrics != nil {
		// Record window duration
		cwm.performanceMetrics.RecordDuration(
			clientinfo.MetricCoordinationWindowDurationSeconds,
			wm.Duration,
		)

		// Record window-level gauges
		cwm.recordWindowGauges(windowIndex, wm)
	}
}

// recordWalletCoordination records metrics for a single wallet's coordination
// in a window.
func (cwm *coordinationWindowMetrics) recordWalletCoordination(
	window *coordinationWindow,
	walletPublicKeyHash [20]byte,
	leader chain.Address,
	actionType string,
	success bool,
	duration time.Duration,
	faults []*coordinationFault,
) {
	cwm.mu.Lock()
	defer cwm.mu.Unlock()

	windowIndex := window.index()
	if windowIndex == 0 {
		return
	}

	wm, exists := cwm.windows[windowIndex]
	if !exists {
		// Window not initialized, initialize it now
		cwm.recordWindowStart(window)
		wm = cwm.windows[windowIndex]
	}

	// Update window-level statistics
	wm.WalletsCoordinated++
	wm.TotalProceduresStarted++
	if success {
		wm.WalletsSuccessful++
		wm.TotalProceduresCompleted++
	} else {
		wm.WalletsFailed++
	}

	// Track leader
	leaderStr := leader.String()
	wm.Leaders[leaderStr]++

	// Track action type
	if actionType != "" {
		wm.ActionTypes[actionType]++
	}

	// Track faults
	faultTypes := make([]string, 0)
	faultCulprits := make([]string, 0)
	for _, fault := range faults {
		faultTypeStr := fault.faultType.String()
		wm.FaultsByType[faultTypeStr]++
		wm.TotalFaults++
		faultTypes = append(faultTypes, faultTypeStr)

		culpritStr := fault.culprit.String()
		wm.FaultsByCulprit[culpritStr]++
		faultCulprits = append(faultCulprits, culpritStr)
	}

	// Record per-wallet detail
	detail := walletCoordinationDetail{
		WalletPublicKeyHash: fmt.Sprintf("0x%x", walletPublicKeyHash),
		Leader:              leaderStr,
		ActionType:          actionType,
		Success:             success,
		Duration:            duration,
		Faults:              faultTypes,
		FaultCulprits:       faultCulprits,
	}
	wm.WalletCoordinationDetails = append(wm.WalletCoordinationDetails, detail)
}

// recordWindowGauges records gauge metrics for a specific window.
func (cwm *coordinationWindowMetrics) recordWindowGauges(
	windowIndex uint64,
	wm *windowMetrics,
) {
	// Record window-level gauges with window index suffix
	// These allow tracking individual window metrics
	windowSuffix := fmt.Sprintf("_window_%d", windowIndex)

	cwm.performanceMetrics.SetGauge(
		clientinfo.MetricCoordinationWindowWalletsCoordinated+windowSuffix,
		float64(wm.WalletsCoordinated),
	)
	cwm.performanceMetrics.SetGauge(
		clientinfo.MetricCoordinationWindowWalletsSuccessful+windowSuffix,
		float64(wm.WalletsSuccessful),
	)
	cwm.performanceMetrics.SetGauge(
		clientinfo.MetricCoordinationWindowWalletsFailed+windowSuffix,
		float64(wm.WalletsFailed),
	)
	cwm.performanceMetrics.SetGauge(
		clientinfo.MetricCoordinationWindowTotalFaults+windowSuffix,
		float64(wm.TotalFaults),
	)
	cwm.performanceMetrics.SetGauge(
		clientinfo.MetricCoordinationWindowCoordinationBlock+windowSuffix,
		float64(wm.CoordinationBlock),
	)
}

// GetWindowMetrics returns metrics for a specific window.
func (cwm *coordinationWindowMetrics) GetWindowMetrics(windowIndex uint64) (*windowMetrics, bool) {
	cwm.mu.RLock()
	defer cwm.mu.RUnlock()

	wm, exists := cwm.windows[windowIndex]
	if !exists {
		return nil, false
	}

	// Return a copy to avoid race conditions
	wmCopy := *wm
	return &wmCopy, true
}

// GetRecentWindows returns metrics for the most recent N windows.
func (cwm *coordinationWindowMetrics) GetRecentWindows(limit int) []*windowMetrics {
	cwm.mu.RLock()
	defer cwm.mu.RUnlock()

	// Collect all window indices and sort them
	indices := make([]uint64, 0, len(cwm.windows))
	for idx := range cwm.windows {
		indices = append(indices, idx)
	}

	// Sort in descending order (most recent first)
	for i := 0; i < len(indices)-1; i++ {
		for j := i + 1; j < len(indices); j++ {
			if indices[i] < indices[j] {
				indices[i], indices[j] = indices[j], indices[i]
			}
		}
	}

	// Limit results
	if limit > 0 && limit < len(indices) {
		indices = indices[:limit]
	}

	// Return copies
	result := make([]*windowMetrics, 0, len(indices))
	for _, idx := range indices {
		wm := cwm.windows[idx]
		wmCopy := *wm
		result = append(result, &wmCopy)
	}

	return result
}

// cleanupOldWindows removes old windows to prevent unbounded memory growth.
func (cwm *coordinationWindowMetrics) cleanupOldWindows() {
	if uint64(len(cwm.windows)) <= cwm.maxWindowsToTrack {
		return
	}

	// Find the oldest window indices
	indices := make([]uint64, 0, len(cwm.windows))
	for idx := range cwm.windows {
		indices = append(indices, idx)
	}

	// Sort in ascending order (oldest first)
	for i := 0; i < len(indices)-1; i++ {
		for j := i + 1; j < len(indices); j++ {
			if indices[i] > indices[j] {
				indices[i], indices[j] = indices[j], indices[i]
			}
		}
	}

	// Remove oldest windows
	windowsToRemove := len(cwm.windows) - int(cwm.maxWindowsToTrack)
	for i := 0; i < windowsToRemove; i++ {
		delete(cwm.windows, indices[i])
	}
}

// GetSummary returns a summary of all tracked windows.
func (cwm *coordinationWindowMetrics) GetSummary() WindowMetricsSummary {
	cwm.mu.RLock()
	defer cwm.mu.RUnlock()

	summary := WindowMetricsSummary{
		TotalWindows:           uint64(len(cwm.windows)),
		TotalWalletsCoordinated: 0,
		TotalWalletsSuccessful:  0,
		TotalWalletsFailed:      0,
		TotalFaults:             0,
		Windows:                 make([]*windowMetrics, 0, len(cwm.windows)),
	}

	for _, wm := range cwm.windows {
		summary.TotalWalletsCoordinated += wm.WalletsCoordinated
		summary.TotalWalletsSuccessful += wm.WalletsSuccessful
		summary.TotalWalletsFailed += wm.WalletsFailed
		summary.TotalFaults += wm.TotalFaults

		wmCopy := *wm
		summary.Windows = append(summary.Windows, &wmCopy)
	}

	return summary
}

// WindowMetricsSummary provides a summary of coordination window metrics.
type WindowMetricsSummary struct {
	TotalWindows           uint64
	TotalWalletsCoordinated uint64
	TotalWalletsSuccessful  uint64
	TotalWalletsFailed      uint64
	TotalFaults             uint64
	Windows                []*windowMetrics
}

// String returns a string representation of window metrics for logging.
func (wm *windowMetrics) String() string {
	return fmt.Sprintf(
		"window[%d] block[%d] wallets[%d/%d/%d] faults[%d] actions[%v]",
		wm.WindowIndex,
		wm.CoordinationBlock,
		wm.WalletsSuccessful,
		wm.WalletsFailed,
		wm.WalletsCoordinated,
		wm.TotalFaults,
		wm.ActionTypes,
	)
}
