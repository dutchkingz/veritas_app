// Arc color and tooltip builders — extracted from globe_controller.js.
// These functions receive a state object so they can read dynamic controller state
// (selectedArcArticleId, currentPerspective) without coupling to the controller class.

import { parseColor, buildGradientStops, hexToRgba, getFramingColor, connectionTypeBadge } from "globe/color_utils"

// state: { selectedArcArticleId, currentPerspective }
export function createArcColorCallback(state) {
  return function arcColorWithDrift(d) {
    if (d?._journey) return d.color || '#00f0ff'

    if (state.selectedArcArticleId && String(d.articleId) === String(state.selectedArcArticleId)) {
      const c = Array.isArray(d.color) ? d.color[0] : (d.color || '#00f0ff')
      const parsed = parseColor(c)
      const bright = {
        r: Math.min(255, parsed.r + Math.round((255 - parsed.r) * 0.5)),
        g: Math.min(255, parsed.g + Math.round((255 - parsed.g) * 0.5)),
        b: Math.min(255, parsed.b + Math.round((255 - parsed.b) * 0.5)),
        a: 1.0
      }
      return `rgba(${bright.r},${bright.g},${bright.b},1)`
    }

    // Network arcs
    if (d.connectionTypes) {
      const threat = d.veritasThreatScore || 0
      const sourceColor = '#4a6070'

      let threatColor, baseOpacity
      if (threat >= 7) { threatColor = '#ff4444'; baseOpacity = 1.0 }
      else if (threat >= 5) { threatColor = '#ff8c00'; baseOpacity = 0.95 }
      else if (threat >= 3) { threatColor = '#ffd700'; baseOpacity = 0.85 }
      else { threatColor = '#6088a0'; baseOpacity = 0.6 }

      const alpha = d.depth >= 2 ? Math.max(baseOpacity * 0.7, 0.5) : baseOpacity

      if (state.currentPerspective !== 'all') {
        const isActive = d.perspectiveSlug === state.currentPerspective
        const dimOpacity = d.perspectiveSlug === 'unclassified' ? 0.35 : 0.1
        if (!isActive) return buildGradientStops(sourceColor, threatColor, dimOpacity)
      }

      return buildGradientStops(sourceColor, threatColor, alpha)
    }

    // Segments with drift data
    if (d.driftIntensity != null && d.sourceName !== undefined) {
      const threat = d.veritasThreatScore || 0
      const vis = d.visibilityWeight || 0.3

      let threatColor
      if (d.gdeltQuadClass === 4) threatColor = '#ff2020'
      else if (d.gdeltQuadClass === 3 || threat >= 7) threatColor = '#ff4444'
      else if (threat >= 5) threatColor = '#ff8c00'
      else if (threat >= 3) threatColor = '#ffd700'
      else threatColor = '#6088a0'

      const sourceColor = '#4a6070'
      const threatBoost = threat >= 5 ? 0.5 : (threat >= 3 ? 0.3 : 0.1)
      const baseAlpha = Math.min(vis * 0.85 + threatBoost, 1.0)

      if (state.selectedArcArticleId) {
        return buildGradientStops(sourceColor, threatColor, 0.2)
      }
      if (state.currentPerspective !== 'all') {
        const isActive = d.perspectiveSlug === state.currentPerspective
        if (!isActive) {
          const dimAlpha = d.perspectiveSlug === 'unclassified' ? 0.35 : 0.12
          return buildGradientStops(sourceColor, threatColor, dimAlpha)
        }
      }
      if (d.tier === 2) {
        return buildGradientStops(sourceColor, threatColor, Math.max(baseAlpha * 0.7, 0.4))
      }
      return buildGradientStops(sourceColor, threatColor, baseAlpha)
    }

    // Fallback: perspective-based color
    return arcColorForPerspective(d, state)
  }
}

function arcColorForPerspective(d, state) {
  if (d?._journey) return d.color || '#00f0ff'

  if (state.selectedArcArticleId && String(d.articleId) === String(state.selectedArcArticleId)) {
    const raw = Array.isArray(d.color) ? d.color[0] : (d.color || '#00f0ff')
    const p = parseColor(raw)
    return `rgba(${Math.min(255, p.r + Math.round((255 - p.r) * 0.5))},${Math.min(255, p.g + Math.round((255 - p.g) * 0.5))},${Math.min(255, p.b + Math.round((255 - p.b) * 0.5))},1)`
  }

  const c = Array.isArray(d.color) ? d.color[0] : (d.color || '#00f0ff')
  const baseTierAlpha = d.tier === 2 ? 0.35 : 1.0

  if (state.selectedArcArticleId) return hexToRgba(c, 0.12)

  if (state.currentPerspective === 'all') {
    return d.tier === 2 ? hexToRgba(c, 0.35) : c
  }
  const isActive = d.perspectiveSlug === state.currentPerspective
  if (isActive) return hexToRgba(c, baseTierAlpha)
  return hexToRgba(c, d.perspectiveSlug === 'unclassified' ? 0.35 : 0.12)
}

export function buildArcTooltip(d) {
  if (!d) return ''

  if (d.connectionTypes) return buildNetworkArcTooltip(d)

  if (d.driftIntensity != null && d.sourceName !== undefined) {
    const framing = d.framingShift || 'unknown'
    const framingColor = getFramingColor(framing)
    const sentimentShift = d.sentimentShift || 'N/A'
    const similarity = d.semanticSimilarity || 0
    const explanation = d.framingExplanation || ''
    const gdeltActorSummary = d.gdeltActorSummary || null
    const gdeltEventDescription = d.gdeltEventDescription || null
    const gdeltGoldsteinScale = d.gdeltGoldsteinScale != null ? d.gdeltGoldsteinScale : null
    const gdeltQuadClassLabel = d.gdeltQuadClassLabel || null
    const threat = d.veritasThreatScore || 0

    const driftLevel = threat >= 7 ? 'CRITICAL' : threat >= 5 ? 'SIGNIFICANT' : threat >= 3 ? 'MODERATE' : 'MINIMAL'
    const driftLevelColor = threat >= 7 ? '#ff2d2d' : threat >= 5 ? '#ff8c00' : threat >= 3 ? '#ffd700' : '#6088a0'

    const headlines = (d.sourceHeadline && d.targetHeadline) ? `
      <div style="font-size:10px;margin-bottom:8px;padding-bottom:8px;border-bottom:1px solid rgba(255,255,255,0.06);">
        <div style="color:#00ffcc;margin-bottom:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:380px;">\u25B8 ${d.sourceHeadline}</div>
        <div style="color:${framingColor};white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:380px;">\u25B8 ${d.targetHeadline}</div>
      </div>
    ` : ''

    return `
      <div style="
        background:rgba(10,12,18,0.92);backdrop-filter:blur(12px);
        border:1px solid ${threat >= 5 ? 'rgba(255,60,60,0.25)' : 'rgba(0,255,204,0.15)'};
        border-left:3px solid ${driftLevelColor};border-radius:6px;padding:14px 18px;
        font-family:'JetBrains Mono','Fira Code','SF Mono',monospace;
        color:#e0e0e0;min-width:320px;max-width:420px;line-height:1.5;
        box-shadow:0 8px 32px rgba(0,0,0,0.5);
      ">
        <div style="font-size:9px;text-transform:uppercase;letter-spacing:2px;color:#607080;margin-bottom:8px;">NARRATIVE DRIFT ANALYSIS</div>
        ${gdeltActorSummary ? `
          <div style="font-size:13px;font-weight:700;color:#ff9090;margin-bottom:6px;">${gdeltActorSummary}</div>
        ` : (d.sourceCountry && d.targetCountry) ? `
          <div style="font-size:12px;margin-bottom:6px;">
            <span style="color:#00ffcc;">${d.sourceCountry}</span>
            <span style="color:#607080;margin:0 6px;">\u2192</span>
            <span style="color:${framingColor};">${d.targetCountry}</span>
          </div>
        ` : ''}
        <div style="font-size:10px;color:#8090a0;margin-bottom:${(d.sourceCountry || gdeltActorSummary) ? '10' : '6'}px;">
          ${d.sourceName || d.sourceCountry || '?'} \u2192 ${d.targetSourceName || d.targetCountry || '?'}
        </div>
        ${headlines}
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:10px;">
          <div><div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#506070;">Threat</div><div style="font-size:11px;color:${driftLevelColor};font-weight:600;">${driftLevel}</div></div>
          <div><div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#506070;">Framing</div><div style="font-size:11px;color:${framingColor};font-weight:600;">${framing.toUpperCase()}</div></div>
          <div><div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#506070;">Sentiment</div><div style="font-size:11px;">${sentimentShift}</div></div>
          <div><div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#506070;">Semantic Match</div><div style="font-size:11px;color:${similarity > 85 ? '#00ffcc' : '#ffd700'};">${similarity}%</div></div>
        </div>
        ${explanation ? `<div style="font-size:10px;color:#8898a8;border-top:1px solid rgba(255,255,255,0.06);padding-top:8px;font-style:italic;">"${explanation}"</div>` : ''}
        <div style="margin-top:10px;">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:4px;">
            <div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#506070;">Score ${threat.toFixed(1)}/10</div>
            <div style="font-size:8px;color:#506070;">conf ${Math.round((d.arcConfidence || 0) * 100)}%</div>
          </div>
          <div style="width:100%;height:4px;background:rgba(255,255,255,0.06);border-radius:2px;overflow:hidden;">
            <div style="width:${Math.round(threat * 10)}%;height:100%;background:linear-gradient(90deg,#6088a0,${driftLevelColor});border-radius:2px;"></div>
          </div>
          ${d.signalBreakdown ? `
            <div style="display:flex;gap:8px;margin-top:5px;font-size:8px;color:#506070;">
              <span>CTX:${d.signalBreakdown.threatContext}</span>
              <span>DFT:${d.signalBreakdown.driftEffective}</span>
              ${d.signalBreakdown.gdeltBonus > 0 ? `<span>GDT:${d.signalBreakdown.gdeltBonus}</span>` : ''}
            </div>
          ` : ''}
        </div>
        ${gdeltActorSummary ? `
          <div style="margin-top:10px;padding-top:8px;border-top:1px solid rgba(255,45,45,0.2);">
            <div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#ff6060;margin-bottom:5px;">CONFLICT INTELLIGENCE</div>
            ${gdeltEventDescription ? `<div style="font-size:10px;color:#c08080;margin-bottom:3px;">${gdeltEventDescription}</div>` : ''}
            <div style="display:flex;gap:10px;margin-top:3px;">
              ${gdeltQuadClassLabel ? `<span style="font-size:9px;color:#a06060;text-transform:uppercase;">${gdeltQuadClassLabel}</span>` : ''}
              ${gdeltGoldsteinScale != null ? `<span style="font-size:9px;color:${gdeltGoldsteinScale < -7 ? '#ff2d2d' : '#ff8060'};">Goldstein: ${gdeltGoldsteinScale.toFixed(1)}</span>` : ''}
            </div>
          </div>
        ` : ''}
      </div>
    `
  }

  // Fallback: legacy tooltip
  const isSegment = d.sourceName !== undefined || d.targetSourceName !== undefined
  const segmentInfo = isSegment ? `
    <div style="color:#a78bfa;font-size:8px;letter-spacing:0.1em;margin-bottom:2px;text-transform:uppercase;">HOP ${(d.segmentIndex || 0) + 1} of ${d.totalSegments || '?'}</div>
    <div style="font-size:10px;margin-bottom:4px;">${d.sourceName || 'Unknown'} \u2192 ${d.targetSourceName || 'Unknown'}</div>
  ` : ''
  return `
    <div style="
      background:rgba(10,12,20,0.92);border:1px solid rgba(0,240,255,0.3);border-radius:4px;
      padding:8px 12px;font-family:'JetBrains Mono',monospace;font-size:11px;
      color:#e0e6ed;line-height:1.4;box-shadow:0 0 20px rgba(0,240,255,0.15);
    ">
      <div style="color:#00f0ff;font-size:9px;letter-spacing:0.1em;margin-bottom:4px;">${isSegment ? 'NARRATIVE SEGMENT' : 'NARRATIVE ARC'}</div>
      ${segmentInfo}
      <div>${d.originCountry || 'Unknown'} \u2192 ${d.targetCountry || 'Unknown'}</div>
      <div style="margin-top:4px;font-weight:600;">${d.headline || 'Linked intelligence signal'}</div>
      <div style="color:#6b7280;font-size:9px;margin-top:4px;">${d.source || 'UNKNOWN SOURCE'}</div>
      ${d.publishedAt ? `<div style="color:#6b7280;font-size:8px;margin-top:2px;">${new Date(d.publishedAt).toLocaleString()}</div>` : ''}
      ${d.strength != null ? `
      <div style="margin-top:6px;padding-top:4px;border-top:1px solid rgba(0,240,255,0.2);display:flex;justify-content:space-between;align-items:center;">
        <span style="color:#22c55e;font-size:8px;letter-spacing:0.08em;">SEMANTIC MATCH</span>
        <span style="color:#22c55e;font-size:10px;font-weight:700;">${Math.round((d.strength || 0) * 100)}%</span>
      </div>` : ''}
    </div>
  `
}

export function createPointColorCallback(state) {
  return function pointColorForPerspective(d) {
    if (d?._journey) return d.color || '#00f0ff'
    const c = d.color || '#00f0ff'
    if (state.currentPerspective === 'all') return c
    if (d.perspectiveSlug === state.currentPerspective) return c
    return hexToRgba(c, d.perspectiveSlug === 'unclassified' ? 0.35 : 0.15)
  }
}

function buildNetworkArcTooltip(d) {
  const score = d.veritasThreatScore || 0
  const strength = d.strength || 0
  const types = (d.connectionTypes || []).map(t => connectionTypeBadge(t)).join(' ')

  const driftLevelColor = score >= 7 ? '#ff2d2d' : score >= 5 ? '#ff8c00' : score >= 3 ? '#ffd700' : '#6088a0'
  const driftLevel = score >= 7 ? 'CRITICAL' : score >= 5 ? 'HIGH' : score >= 3 ? 'MODERATE' : 'LOW'

  const sourceName = d.sourceName || d.sourceCountry || 'Source'
  const targetName = d.targetSourceName || d.targetCountry || 'Target'

  let headlines = ''
  if (d.sourceHeadline || d.targetHeadline) {
    headlines = `<div style="font-size:10px;margin-bottom:8px;padding-bottom:8px;border-bottom:1px solid rgba(255,255,255,0.06);">`
    if (d.sourceHeadline) headlines += `<div style="color:#00ffcc;margin-bottom:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:380px;">&#9656; ${d.sourceHeadline}</div>`
    if (d.targetHeadline) headlines += `<div style="color:#c0d0e0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:380px;">&#9656; ${d.targetHeadline}</div>`
    headlines += `</div>`
  }

  let analysisGrid = ''
  const cells = []
  if (d.framing) cells.push({ label: 'Framing', value: d.framing.toUpperCase(), color: getFramingColor(d.framing) })
  if (d.sentimentShift) cells.push({ label: 'Sentiment', value: d.sentimentShift, color: '#e0e0e0' })
  if (d.semanticSimilarity) cells.push({ label: 'Semantic Match', value: `${d.semanticSimilarity}%`, color: d.semanticSimilarity > 85 ? '#00ffcc' : '#ffd700' })
  if (d.depth) cells.push({ label: 'Depth', value: `${d.depth}`, color: '#8090a0' })

  if (cells.length > 0) {
    analysisGrid = `<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:10px;">`
    cells.forEach(c => {
      analysisGrid += `<div><div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#506070;">${c.label}</div><div style="font-size:11px;color:${c.color};font-weight:600;">${c.value}</div></div>`
    })
    analysisGrid += `</div>`
  }

  let gdeltSection = ''
  if (d.actorSummary || d.eventDescription) {
    gdeltSection = `
      <div style="margin-top:10px;padding-top:8px;border-top:1px solid rgba(255,45,45,0.2);">
        <div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#ff6060;margin-bottom:5px;">CONFLICT INTELLIGENCE</div>
        ${d.actorSummary ? `<div style="font-size:10px;color:#ff9090;font-weight:600;margin-bottom:3px;">${d.actorSummary}</div>` : ''}
        ${d.eventDescription ? `<div style="font-size:10px;color:#c08080;">${d.eventDescription}</div>` : ''}
        ${d.goldsteinScale != null ? `<div style="font-size:9px;color:${d.goldsteinScale < -7 ? '#ff2d2d' : '#ff8060'};margin-top:3px;">Goldstein: ${d.goldsteinScale.toFixed(1)}</div>` : ''}
      </div>`
  }

  let entitySection = ''
  if (d.sharedEntities && d.sharedEntities.length > 0) {
    entitySection = `
      <div style="margin-top:8px;padding-top:8px;border-top:1px solid rgba(0,255,204,0.1);">
        <div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#00c0a0;margin-bottom:4px;">SHARED ENTITIES (${d.sharedEntityCount || d.sharedEntities.length})</div>
        <div style="font-size:10px;color:#80c0b0;">${d.sharedEntities.join(', ')}</div>
      </div>`
  }

  return `
    <div style="
      background:rgba(10,12,18,0.92);backdrop-filter:blur(12px);
      border:1px solid ${score >= 5 ? 'rgba(255,60,60,0.25)' : 'rgba(0,255,204,0.15)'};
      border-left:3px solid ${driftLevelColor};border-radius:6px;padding:14px 18px;
      font-family:'JetBrains Mono','Fira Code','SF Mono',monospace;
      color:#e0e0e0;min-width:320px;max-width:420px;line-height:1.5;
      box-shadow:0 8px 32px rgba(0,0,0,0.5);
    ">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
        <div style="font-size:9px;text-transform:uppercase;letter-spacing:2px;color:#607080;">NARRATIVE NETWORK</div>
        <div style="display:flex;gap:4px;">${types}</div>
      </div>
      <div style="font-size:12px;margin-bottom:6px;">
        <span style="color:#00ffcc;">${sourceName}</span>
        <span style="color:#607080;margin:0 6px;">&rarr;</span>
        <span style="color:#c0d0e0;">${targetName}</span>
      </div>
      ${headlines}
      ${analysisGrid}
      <div style="margin-top:8px;">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:4px;">
          <div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#506070;">Threat ${score.toFixed(1)}/10 &middot; ${driftLevel}</div>
          <div style="font-size:8px;color:#506070;">strength ${Math.round(strength * 100)}%</div>
        </div>
        <div style="width:100%;height:4px;background:rgba(255,255,255,0.06);border-radius:2px;overflow:hidden;">
          <div style="width:${Math.round(score * 10)}%;height:100%;background:linear-gradient(90deg,#6088a0,${driftLevelColor});border-radius:2px;"></div>
        </div>
      </div>
      ${gdeltSection}
      ${entitySection}
    </div>`
}
