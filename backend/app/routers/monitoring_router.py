"""Monitoring Router — Observability Dashboard

Servis: logs/nexus.log dosyasını analiz ederek:
- Hangi şarkılarda hata olduğunu
- Hangi proxy'lerin engellendiğini
- Invidious fallback istatistiklerini
- Gerçek zamanlı endpoint kullanımını gösterir
"""

from fastapi import APIRouter, Query, HTTPException
from fastapi.responses import HTMLResponse

from app.services.monitoring import parse_logs

router = APIRouter(prefix="/monitoring", tags=["Monitoring"])


@router.get("/stats")
async def get_stats(hours: int = Query(24, ge=1, le=168, description="Son kaç saatin verisi?")):
    """Log istatistiklerini JSON olarak döndür."""
    stats = parse_logs(hours=hours)
    return stats


@router.get("/dashboard", response_class=HTMLResponse)
async def get_dashboard(hours: int = Query(24, ge=1, le=168)):
    """HTML görsel dashboard — Chart.js ile görselleştirilmiş."""
    stats = parse_logs(hours=hours)

    if "error" in stats:
        return HTMLResponse(f"""
        <html><body style="background:#121212;color:white;font-family:sans-serif;padding:40px">
        <h1>⚠️ {stats['error']}</h1>
        <p>Önce uygulamayı çalıştır ve birkaç istek yap.</p>
        <code>cd backend && uvicorn app.main:app --reload --port 8000</code>
        </body></html>
        """)

    # Prepare data for charts
    levels_json = json.dumps(stats.get("by_level", {}))
    sources_json = json.dumps(stats.get("by_source", {}))
    timeseries_labels = json.dumps(stats["timeseries"]["labels"])
    timeseries_values = json.dumps(stats["timeseries"]["values"])
    endpoint_hits = json.dumps(stats.get("endpoint_hits", {}))
    top_errors = json.dumps(stats.get("top_error_songs", []))
    proxy_stats = stats.get("proxy_stats", {})
    recent_errors = stats.get("recent_errors", [])

    return HTMLResponse(f"""
    <!DOCTYPE html>
    <html lang="tr">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Nexus Monitoring Dashboard</title>
        <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
        <style>
            * {{ margin: 0; padding: 0; box-sizing: border-box; }}
            body {{ background: #121212; color: #e0e0e0; font-family: 'Segoe UI', sans-serif; padding: 20px; }}
            .header {{ display: flex; justify-content: space-between; align-items: center; margin-bottom: 30px; }}
            .header h1 {{ color: #1DB954; font-size: 28px; }}
            .header h1 span {{ color: #727272; font-size: 14px; }}
            .header .badge {{ background: #282828; padding: 8px 16px; border-radius: 20px; font-size: 13px; }}
            .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }}
            .card {{ background: #1E1E1E; border-radius: 12px; padding: 20px; }}
            .card h2 {{ color: #fff; font-size: 16px; margin-bottom: 16px; opacity: 0.8; }}
            .card .value {{ font-size: 36px; font-weight: 700; color: #1DB954; }}
            .card .sub {{ color: #727272; font-size: 13px; margin-top: 4px; }}
            .stat-row {{ display: flex; justify-content: space-between; padding: 6px 0; border-bottom: 1px solid #333; }}
            .stat-row:last-child {{ border: none; }}
            .error-item {{ padding: 8px; margin: 4px 0; background: #2a1a1a; border-radius: 6px; font-size: 12px; }}
            .error-item .time {{ color: #E55C5C; }}
            .error-item .msg {{ color: #b3b3b3; }}
            canvas {{ max-height: 200px; }}
            .errors-container {{ max-height: 300px; overflow-y: auto; }}
            .top-songs {{ display: flex; flex-wrap: wrap; gap: 6px; }}
            .top-songs .tag {{ background: #2a1a1a; color: #E55C5C; padding: 4px 10px; border-radius: 12px; font-size: 12px; }}
            .progress {{ height: 6px; background: #333; border-radius: 3px; margin: 8px 0; overflow: hidden; }}
            .progress-bar {{ height: 100%; background: #1DB954; border-radius: 3px; transition: width 0.3s; }}
            .progress-bar.warning {{ background: #E55C5C; }}
        </style>
    </head>
    <body>
        <div class="header">
            <div>
                <h1>🎵 Nexus <span>Monitoring</span></h1>
                <p style="color:#727272;font-size:13px;margin-top:4px">{stats['time_range']} • {stats['total_lines_analyzed']} log satırı analiz edildi</p>
            </div>
            <div class="badge">📁 {stats.get('logs_size_mb', 0)} MB</div>
        </div>

        <div class="grid">
            <!-- KPI Cards -->
            <div class="card">
                <h2>📊 Log Seviyeleri</h2>
                <div class="stat-row"><span>✅ INFO</span><span style="color:#1DB954">{stats['by_level'].get('INFO', 0)}</span></div>
                <div class="stat-row"><span>⚠️ WARNING</span><span style="color:#FFA500">{stats['by_level'].get('WARNING', 0)}</span></div>
                <div class="stat-row"><span>❌ ERROR</span><span style="color:#E55C5C">{stats['by_level'].get('ERROR', 0)}</span></div>
                <div class="stat-row"><span>🔍 DEBUG</span><span style="color:#4A90D9">{stats['by_level'].get('DEBUG', 0)}</span></div>
            </div>

            <div class="card">
                <h2>🎯 Kaynak Kullanımı</h2>
                <div class="stat-row"><span>🎬 yt-dlp</span><span style="color:#1DB954">{stats['by_source'].get('yt-dlp', 0)}</span></div>
                <div class="stat-row"><span>🌐 Invidious</span><span style="color:#FFA500">{stats['by_source'].get('invidious', 0)}</span></div>
                <div class="stat-row"><span>🔌 Proxy</span><span style="color:#4A90D9">{stats['by_source'].get('proxy', 0)}</span></div>
            </div>

            <div class="card">
                <h2>🛡️ Proxy Durumu</h2>
                <div class="value">{proxy_stats.get('stability_percent', 0)}%</div>
                <div class="sub">stabilite</div>
                <div class="progress">
                    <div class="progress-bar {'warning' if proxy_stats.get('stability_percent', 100) < 70 else ''}"
                         style="width:{proxy_stats.get('stability_percent', 0)}%"></div>
                </div>
                <div class="stat-row"><span>Toplam istek</span><span>{proxy_stats.get('total_requests', 0)}</span></div>
                <div class="stat-row"><span>Engellenen</span><span style="color:#E55C5C">{proxy_stats.get('blocked', 0)}</span></div>
            </div>

            <div class="card">
                <h2>🚦 Throttle & Fallback</h2>
                <div class="stat-row"><span>⏱️ YouTube Throttle (429)</span><span style="color:#FFA500">{stats.get('throttle_events', 0)}</span></div>
                <div class="stat-row"><span>🔄 Invidious Fallback</span><span style="color:#4A90D9">{stats.get('invidious_fallbacks', 0)}</span></div>
            </div>

            <!-- Zaman Serisi Grafiği -->
            <div class="card" style="grid-column: span 2;">
                <h2>📈 İstek Zaman Serisi (5dk aralıklarla)</h2>
                <canvas id="timeChart"></canvas>
            </div>

            <!-- Endpoint Kullanımı -->
            <div class="card">
                <h2>🔗 En Çok Kullanılan Endpoint'ler</h2>
                <div id="endpointList"></div>
            </div>

            <!-- En Çok Hata Alan Şarkılar -->
            <div class="card">
                <h2>🎵 En Çok Hata Alan Şarkılar</h2>
                <div class="top-songs" id="topErrorSongs"></div>
                <div style="margin-top:12px;font-size:12px;color:#727272">
                    Bu şarkılar Invidious veya proxy havuzuna eklenmeli
                </div>
            </div>

            <!-- Son Hatalar -->
            <div class="card" style="grid-column: span 2;">
                <h2>❌ Son 20 Hata</h2>
                <div class="errors-container" id="recentErrors"></div>
            </div>
        </div>

        <script>
            // Time series chart
            new Chart(document.getElementById('timeChart'), {{
                type: 'line',
                data: {{
                    labels: {timeseries_labels},
                    datasets: [{{
                        label: 'İstek / 5dk',
                        data: {timeseries_values},
                        borderColor: '#1DB954',
                        backgroundColor: 'rgba(29,185,84,0.1)',
                        fill: true,
                        tension: 0.3,
                        pointRadius: 2,
                    }}]
                }},
                options: {{
                    responsive: true,
                    plugins: {{ legend: {{ display: false }} }},
                    scales: {{
                        x: {{ ticks: {{ color: '#727272', maxTicksLimit: 10 }}, grid: {{ color: '#333' }} }},
                        y: {{ beginAtZero: true, ticks: {{ color: '#727272' }}, grid: {{ color: '#333' }} }}
                    }}
                }}
            }});

            // Endpoint list
            const endpoints = {endpoint_hits};
            const endpointList = document.getElementById('endpointList');
            Object.entries(endpoints).slice(0, 10).forEach(([ep, count]) => {{
                const div = document.createElement('div');
                div.className = 'stat-row';
                div.innerHTML = `<span style="font-family:monospace;font-size:12px">${{ep}}</span><span>${{count}}</span>`;
                endpointList.appendChild(div);
            }});

            // Top error songs
            const topErrors = {top_errors};
            const errorSongsDiv = document.getElementById('topErrorSongs');
            if (topErrors.length === 0) {{
                errorSongsDiv.innerHTML = '<span style="color:#727272;font-size:13px">Henüz hata kaydı yok ✅</span>';
            }} else {{
                topErrors.slice(0, 10).forEach(s => {{
                    const tag = document.createElement('span');
                    tag.className = 'tag';
                    tag.innerHTML = `${{s.youtube_id}} (${{s.errors}})`;
                    errorSongsDiv.appendChild(tag);
                }});
            }}

            // Recent errors
            const recentErrors = {json.dumps(recent_errors)};
            const errorsDiv = document.getElementById('recentErrors');
            if (recentErrors.length === 0) {{
                errorsDiv.innerHTML = '<p style="color:#727272;font-size:13px">Son 24 saatte hata yok 🎉</p>';
            }} else {{
                recentErrors.slice(0, 20).forEach(err => {{
                    const div = document.createElement('div');
                    div.className = 'error-item';
                    div.innerHTML = `<span class="time">[${{err.time}}]</span> <span class="msg">${{err.message}}</span>`;
                    errorsDiv.appendChild(div);
                }});
            }}
        </script>
    </body>
    </html>
    """)