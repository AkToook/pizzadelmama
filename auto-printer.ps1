# AUTO-PRINTER — New Pizza Reims
# Double-cliquez sur ce fichier pour lancer
# Ctrl+C pour arreter

$PROJECT_ID = 'pizza-reims'
$API_KEY = 'AIzaSyBc4KLK4E6p5rEmQBcdghX2YesveHyT2NU'
$POLL_INTERVAL = 5
$PRINTED_FILE = Join-Path $PSScriptRoot '.printed-orders.json'

# Charger commandes deja imprimees
$printedOrders = @{}
if (Test-Path $PRINTED_FILE) {
    try {
        $data = Get-Content $PRINTED_FILE -Raw | ConvertFrom-Json
        foreach ($id in $data) { $printedOrders[$id] = $true }
        Write-Host "Charge $($printedOrders.Count) commandes deja imprimees" -ForegroundColor Gray
    } catch {}
}

function Save-Printed {
    $printedOrders.Keys | ConvertTo-Json | Set-Content $PRINTED_FILE -Encoding UTF8
}

function Build-Ticket($order) {
    $ESC = [char]0x1B
    $GS = [char]0x1D
    $t = "${ESC}@"
    $t += "${ESC}E$([char]1)"
    $t += "${ESC}G$([char]1)"
    $t += "${ESC}a$([char]1)"
    $t += "${ESC}!$([char]0x30)"
    $t += "NEW PIZZA REIMS`n"
    $t += "${ESC}!$([char]0)"
    $t += "41 rue du Mont d'Arene`n"
    $t += "Tel: 03 26 04 30 51`n"
    $t += "================================`n"
    $t += "${ESC}a$([char]0)"

    $num = if ($order.orderNum) { $order.orderNum } else { '---' }
    $timeStr = '--:--'
    if ($order.createdAt) {
        try {
            $dt = [DateTime]::Parse($order.createdAt)
            $timeStr = $dt.ToString('HH:mm')
        } catch {}
    }

    $t += "${ESC}!$([char]0x30)"
    $t += "N. $num`n"
    $t += "${ESC}!$([char]0)"
    $t += "Heure: $timeStr`n"
    $t += "================================`n"
    $mode = if ($order.deliveryMode -eq 'livraison') { 'LIVRAISON' } else { 'A EMPORTER' }
    $t += "Mode  : $mode`n"
    $t += "Client: $($order.customerName)`n"
    $t += "Tel   : $($order.customerPhone)`n"
    if ($order.deliveryMode -eq 'livraison' -and $order.address) {
        $t += "Adresse: $($order.address)`n"
    }
    $t += "================================`n"

    foreach ($item in $order.items) {
        $price = [math]::Round([double]$item.price, 2)
        $t += "$($item.name)  ${price}EUR`n"
        if ($item.details) { $t += "  > $($item.details)`n" }
    }

    $t += "================================`n"
    $t += "${ESC}a$([char]1)"
    $t += "${ESC}!$([char]0x30)"
    $total = [math]::Round([double]$order.total, 2)
    $t += "TOTAL: ${total} EUR`n"
    $t += "${ESC}!$([char]0)"
    $pay = if ($order.status -eq 'PAYED_CASH') { 'ESPECES' } else { 'CARTE' }
    $t += "Paiement: $pay`n"

    if ($order.special) {
        $t += "================================`n"
        $t += "${ESC}a$([char]0)"
        $t += "NOTE: $($order.special)`n"
    }

    $t += "================================`n"
    $t += "${ESC}a$([char]1)"
    $t += "Merci de votre commande !`n"
    $t += "New Pizza Reims - 7j/7`n"
    $t += "`n`n`n`n"
    $t += "${GS}V$([char]0x42)$([char]0)"
    return $t
}

function Print-Ticket($order, $docId) {
    $ticket = Build-Ticket $order
    $tmpFile = Join-Path $env:TEMP 'ticket.bin'
    
    $encoding = [System.Text.Encoding]::GetEncoding(437)
    [System.IO.File]::WriteAllBytes($tmpFile, $encoding.GetBytes($ticket))

    # Try known printer names
    $printers = @('XP-80(copy1)', 'XP-80')
    
    # Add default printer
    try {
        $default = (Get-WmiObject -Query "SELECT * FROM Win32_Printer WHERE Default=True").Name
        if ($default -and $default -notin $printers) { $printers += $default }
    } catch {}

    $success = $false
    foreach ($printer in $printers) {
        try {
            $share = "\\$env:COMPUTERNAME\$printer"
            $result = cmd /c "copy /b `"$tmpFile`" `"$share`"" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Ticket imprime sur: $printer" -ForegroundColor Green
                $success = $true
                break
            }
        } catch {}
    }

    if (-not $success) {
        # Fallback: direct port
        try {
            $port = (Get-WmiObject -Query "SELECT * FROM Win32_Printer WHERE Name='$($printers[0])'").PortName
            if ($port) {
                [System.IO.File]::Copy($tmpFile, $port, $true)
                Write-Host "  Ticket imprime via port: $port" -ForegroundColor Green
                $success = $true
            }
        } catch {}
    }

    if ($success) {
        $printedOrders[$docId] = $true
        Save-Printed

        # Update Firebase
        try {
            $url = "https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/orders/${docId}?updateMask.fieldPaths=printed&key=$API_KEY"
            $body = '{"fields":{"printed":{"booleanValue":true}}}'
            Invoke-RestMethod -Uri $url -Method Patch -Body $body -ContentType 'application/json' | Out-Null
            Write-Host "  Firebase: printed=true" -ForegroundColor Gray
        } catch {}
    } else {
        Write-Host "  ERREUR: aucune imprimante trouvee" -ForegroundColor Red
    }
}

function Check-Orders {
    try {
        $url = "https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/orders?key=$API_KEY"
        $resp = Invoke-RestMethod -Uri $url -TimeoutSec 10
        
        foreach ($doc in $resp.documents) {
            $docId = $doc.name.Split('/')[-1]
            $fields = $doc.fields
            
            $status = $fields.status.stringValue
            $isPrinted = $fields.printed.booleanValue

            if (-not $isPrinted -and -not $printedOrders.ContainsKey($docId) -and ($status -eq 'PAYED_CASH' -or $status -eq 'PAYED_CARD')) {
                $items = @()
                if ($fields.items.arrayValue.values) {
                    foreach ($v in $fields.items.arrayValue.values) {
                        $f = $v.mapValue.fields
                        $items += @{
                            name = $f.name.stringValue
                            price = if ($f.price.doubleValue) { $f.price.doubleValue } elseif ($f.price.stringValue) { $f.price.stringValue } else { 0 }
                            details = $f.details.stringValue
                        }
                    }
                }

                $order = @{
                    orderNum = $fields.orderNum.stringValue
                    customerName = $fields.customerName.stringValue
                    customerPhone = $fields.customerPhone.stringValue
                    deliveryMode = $fields.deliveryMode.stringValue
                    address = $fields.address.stringValue
                    total = if ($fields.total.doubleValue) { $fields.total.doubleValue } else { $fields.total.integerValue }
                    status = $status
                    special = $fields.special.stringValue
                    createdAt = $fields.createdAt.timestampValue
                    items = $items
                }

                Write-Host "`n--- NOUVELLE COMMANDE ---" -ForegroundColor Yellow
                Write-Host "  $($order.orderNum) - $($order.customerName) - $($order.total)EUR" -ForegroundColor Cyan
                Print-Ticket $order $docId
            }
        }
    } catch {
        Write-Host "Erreur connexion: $_" -ForegroundColor Red
    }
}

Clear-Host
Write-Host ""
Write-Host "========================================" -ForegroundColor Red
Write-Host "  AUTO-PRINTER - New Pizza Reims" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Red
Write-Host "En ecoute des nouvelles commandes..." -ForegroundColor Green
Write-Host "Appuyez sur Ctrl+C pour arreter" -ForegroundColor Gray
Write-Host ""

while ($true) {
    Check-Orders
    Start-Sleep -Seconds $POLL_INTERVAL
}
