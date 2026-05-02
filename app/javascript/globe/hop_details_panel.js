// Hop Details Panel — renders segment details in the sidebar.
// Pure DOM rendering, no globe dependency.

export function showHopDetails(segment) {
  const container = document.getElementById('hop-details')
  const emptyMsg = document.querySelector('.hop-timeline-empty')
  if (!container || !emptyMsg) return

  emptyMsg.classList.add('d-none')
  container.classList.remove('d-none')

  const publishedAt = segment.publishedAt ? new Date(segment.publishedAt) : null
  const dateStr = publishedAt ? publishedAt.toLocaleString() : 'Unknown'

  const framingColor = segment.color || '#00f0ff'
  let framingLabel = 'Unknown'
  if (framingColor === '#22c55e') framingLabel = 'Original'
  else if (framingColor === '#f59e0b') framingLabel = 'Amplified'
  else if (framingColor === '#ef4444') framingLabel = 'Distorted'
  else if (framingColor === '#3b82f6') framingLabel = 'Neutralized'

  container.innerHTML = `
    <div class="veritas-feed-card mb-3">
      <div class="d-flex justify-content-between align-items-center mb-2">
        <span class="feed-source text-uppercase" style="font-size: 0.8rem; color: #00f0ff;">
          ${segment.routeName || 'Unnamed Route'}
        </span>
        <span class="badge bg-dark" style="font-size: 0.7rem;">
          Hop ${segment.segmentIndex + 1} of ${segment.totalSegments}
        </span>
      </div>

      <div class="d-flex justify-content-between align-items-center mb-3">
        <div class="text-center">
          <div class="fw-bold">${segment.sourceName || 'Unknown'}</div>
          <div class="text-muted" style="font-size: 0.75rem;">
            ${segment.startLat.toFixed(2)}\u00B0, ${segment.startLng.toFixed(2)}\u00B0
          </div>
        </div>
        <div class="text-primary mx-3">\u2192</div>
        <div class="text-center">
          <div class="fw-bold">${segment.targetSourceName || 'Unknown'}</div>
          <div class="text-muted" style="font-size: 0.75rem;">
            ${segment.endLat.toFixed(2)}\u00B0, ${segment.endLng.toFixed(2)}\u00B0
          </div>
        </div>
      </div>

      <div class="row g-2 mb-3">
        <div class="col-6">
          <div class="border rounded p-2">
            <div class="text-muted" style="font-size: 0.75rem;">Framing</div>
            <div class="fw-bold" style="color: ${framingColor}">${framingLabel}</div>
          </div>
        </div>
        <div class="col-6">
          <div class="border rounded p-2">
            <div class="text-muted" style="font-size: 0.75rem;">Delay</div>
            <div class="fw-bold">${segment.delaySeconds || 0}s</div>
          </div>
        </div>
        <div class="col-12">
          <div class="border rounded p-2">
            <div class="text-muted" style="font-size: 0.75rem;">Published</div>
            <div class="fw-bold">${dateStr}</div>
          </div>
        </div>
      </div>

      ${segment.headline ? `
        <div class="border-start border-3 border-info ps-3 mb-3">
          <div class="text-muted" style="font-size: 0.75rem;">Headline</div>
          <div class="fw-bold">${segment.headline}</div>
        </div>
      ` : ''}

      ${segment.framingExplanation ? `
        <div class="border-start border-3 ps-3 mb-3" style="border-color: ${framingColor} !important;">
          <div class="text-muted" style="font-size: 0.75rem;">Why ${framingLabel}</div>
          <div style="font-size: 0.85rem; color: #cbd5e1;">${segment.framingExplanation}</div>
        </div>
      ` : ''}

      <div class="d-flex justify-content-between border-top pt-2">
        <div class="text-center">
          <div class="text-muted" style="font-size: 0.7rem;">Manipulation</div>
          <div class="fw-bold ${segment.manipulationScore > 0.7 ? 'text-danger' : segment.manipulationScore > 0.3 ? 'text-warning' : 'text-success'}">
            ${(segment.manipulationScore * 100).toFixed(1)}%
          </div>
        </div>
        <div class="text-center">
          <div class="text-muted" style="font-size: 0.7rem;">Amplification</div>
          <div class="fw-bold ${segment.amplificationScore > 0.7 ? 'text-success' : segment.amplificationScore > 0.3 ? 'text-warning' : 'text-muted'}">
            ${(segment.amplificationScore * 100).toFixed(1)}%
          </div>
        </div>
        <div class="text-center">
          <div class="text-muted" style="font-size: 0.7rem;">Total Hops</div>
          <div class="fw-bold">${segment.totalHops || 0}</div>
        </div>
      </div>
    </div>
  `
}
