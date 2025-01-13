#!/usr/bin/expect

# 讀取環境變數 MULTIPASS_PASSPHRASE
set password $env(MULTIPASS_PASSPHRASE)

# 檢查密碼是否已設定
if { [string length $password] == 0 } {
  puts "Error: MULTIPASS_PASSPHRASE environment variable is not set."
  exit 1
}

# 顯示產生的密碼 (可選)
# puts "Password: $password" 

# 設定 Multipass passphrase
spawn multipass set local.passphrase

expect "Enter the passphrase:"
send "$password\r"

expect "Confirm the passphrase:"
send "$password\r"

expect eof

