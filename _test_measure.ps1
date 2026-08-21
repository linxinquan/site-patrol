$server = Start-Process python -ArgumentList 'c:\sp\server\measure_server.py','8820' -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 2

# 健康检查
Write-Host "== health =="
(Invoke-WebRequest -Uri http://localhost:8820/health -UseBasicParsing).Content

# 保存一次会话
Write-Host "== POST =="
$body = '{"id":"p1_d1_1","projectKey":"p1","drawingKey":"d1","floor":"3F","tolMm":5,"tolPct":2,"photoCalib":{"refMm":1000,"pixA":10,"pixB":200,"imgW":1920},"items":[{"name":"梁宽","drawingMm":300,"photoMm":305}],"updatedAt":123}'
(Invoke-WebRequest -Uri http://localhost:8820/api/measurements -Method POST -ContentType 'application/json' -Body $body -UseBasicParsing).Content

# 读取
Write-Host "== GET =="
(Invoke-WebRequest -Uri "http://localhost:8820/api/measurements?projectKey=p1&drawingKey=d1" -UseBasicParsing).Content

# 停止
Stop-Process -Id $server.Id -Force
Write-Host "---TEST DONE---"
