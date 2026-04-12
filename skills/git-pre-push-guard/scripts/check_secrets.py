#!/usr/bin/env python3
"""
GitHub Pre-Push Guard - 敏感信息检测器
扫描文件内容中的敏感信息（API Key、密码、Token、密钥、个人信息等）
"""

import re
import sys
import os
import argparse
from pathlib import Path
from dataclasses import dataclass
from typing import List, Tuple

# ─── 检测规则 ─────────────────────────────────────────────
# 风险等级: HIGH(确认敏感) / MEDIUM(疑似敏感) / LOW(可能误报)

PATTERNS: List[Tuple[str, re.Pattern, str, str]] = [
    # ═══════════════════════════════════════════
    #  HIGH - 确认敏感信息
    # ═══════════════════════════════════════════

    # ── 个人信息 (PII) ──
    ("中国身份证号", re.compile(r'[1-9]\d{5}(?:19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\d{3}[\dXx]'), "HIGH", "pii"),
    ("中国手机号", re.compile(r'1[3-9]\d{9}'), "HIGH", "pii"),
    ("中国银行卡号", re.compile(r'\b(?:62|35|4|5|6)\d{14,18}\b'), "HIGH", "pii"),
    ("护照号", re.compile(r'(?i)(?:passport|护照)[#:\s]*[A-Z0-9]{8,12}'), "HIGH", "pii"),
    ("邮箱+密码组合", re.compile(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\s*[:;,|]\s*[A-Za-z0-9@#$%^&*!]{6,}'), "HIGH", "pii"),
    ("姓名+身份证", re.compile(r'(?i)(?:姓名|name)\s*[=:]\s*\S+\s*(?:身份证|id|id[_\-]card)\s*[=:]\s*[1-9]\d{5}(?:19|20)\d{2}'), "LOW", "pii"),
    ("地址+电话", re.compile(r'(?i)(?:address|地址|addr)\s*[=:]\s*\S+.*1[3-9]\d{9}'), "LOW", "pii"),

    # ═══════════════════════════════════════════
    #  数据库连接串（账号密码）
    # ═══════════════════════════════════════════

    # ── 关系型数据库 ──
    ("MySQL 连接串", re.compile(r'mysql(?:e)?://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("PostgreSQL 连接串", re.compile(r'postgresql?://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("SQL Server 连接串", re.compile(r'(?:sqlserver|mssql)://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("Oracle 连接串", re.compile(r'oracle(?:db)?://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("MariaDB 连接串", re.compile(r'mariadb://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("SQLite 路径", re.compile(r'sqlite:///(?:/|[A-Z]:)?[^\s"\'<>]+'), "MEDIUM", "database"),
    ("JDBC MySQL", re.compile(r'jdbc:mysql://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("JDBC PostgreSQL", re.compile(r'jdbc:postgresql://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("JDBC Oracle", re.compile(r'jdbc:oracle:(?:thin:@|oci:)//?[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("JDBC SQL Server", re.compile(r'jdbc:sqlserver://[^\s"\'<>]+;[^\s"\'<>]*password=[^\s"\'<>]+'), "HIGH", "database"),

    # ── NoSQL 数据库 ──
    ("MongoDB 连接串", re.compile(r'mongodb(\+srv)?://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("CouchDB 连接串", re.compile(r'couchdb://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("Cassandra 连接串", re.compile(r'cassandra://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("RethinkDB 连接串", re.compile(r'rethinkdb://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("ArangoDB 连接串", re.compile(r'arangodb://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("Neo4j 连接串", re.compile(r'neo4j://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("FaunaDB 连接串", re.compile(r'fauna://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),

    # ── 缓存/消息队列 ──
    ("Redis 连接串", re.compile(r'redis(?:s)?://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("Memcached 连接串", re.compile(r'memcached://[^\s"\'<>]+:[^\s"\'<>]+@'), "MEDIUM", "database"),
    ("RabbitMQ 连接串", re.compile(r'amqp(?:s)?://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("Kafka 连接串", re.compile(r'kafka://[^\s"\'<>]+:[^\s"\'<>]+@'), "MEDIUM", "database"),
    ("NATS 连接串", re.compile(r'nats://[^\s"\'<>]+:[^\s"\'<>]+@'), "MEDIUM", "database"),
    ("ActiveMQ 连接串", re.compile(r'(?:activemq|stomp)://[^\s"\'<>]+:[^\s"\'<>]+@'), "MEDIUM", "database"),
    ("ZeroMQ 连接串", re.compile(r'zmq://[^\s"\'<>]+:[^\s"\'<>]+@'), "MEDIUM", "database"),
    ("Elasticsearch 连接串", re.compile(r'(?:elasticsearch|es)://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("ClickHouse 连接串", re.compile(r'clickhouse://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("InfluxDB 连接串", re.compile(r'influxdb://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("TimescaleDB 连接串", re.compile(r'timescaledb://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),
    ("DynamoDB 连接串", re.compile(r'dynamodb://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "database"),

    # ═══════════════════════════════════════════
    #  国内云服务
    # ═══════════════════════════════════════════

    # ── 阿里云 ──
    ("阿里云 AccessKey ID", re.compile(r'LTAI[A-Za-z0-9]{12,20}'), "HIGH", "cloud"),
    ("阿里云 AccessKey Secret", re.compile(r'(?i)(?:aliyun|alibaba)[_\-]?(?:secret|access[_\-]?key)\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "cloud"),
    ("阿里云短信 Key", re.compile(r'(?i)aliyun[_\-]?sms[_\-]?(?:key|secret)\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "cloud"),
    ("阿里云 OSS Endpoint", re.compile(r'oss-[a-z0-9]+\.aliyuncs\.com'), "MEDIUM", "cloud"),

    # ── 腾讯云 ──
    ("腾讯云 SecretId", re.compile(r'(?i)(?:tencent|qcloud)[_\-]?secret[_\-]?id\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "cloud"),
    ("腾讯云 SecretKey", re.compile(r'(?i)(?:tencent|qcloud)[_\-]?secret[_\-]?key\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "cloud"),
    ("腾讯云 COS Endpoint", re.compile(r'cos\.[a-z0-9-]+\.myqcloud\.com'), "MEDIUM", "cloud"),

    # ── 华为云 ──
    ("华为云 AccessKey", re.compile(r'(?i)(?:huawei|hwcloud)[_\-]?(?:access[_\-]?key|secret)\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "cloud"),
    ("华为云 OBS Endpoint", re.compile(r'obs\.[a-z0-9-]+\.myhuaweicloud\.com'), "MEDIUM", "cloud"),

    # ── 百度 ──
    ("百度 API Key", re.compile(r'(?i)baidu[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "api_key"),
    ("百度 Secret Key", re.compile(r'(?i)baidu[_\-]?secret[_\-]?key\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "api_key"),
    ("百度 BOS Endpoint", re.compile(r'\.bj\.bcebos\.com'), "MEDIUM", "cloud"),

    # ── 地图服务 ──
    ("高德地图 Key", re.compile(r'(?i)(?:amap|gaode)[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "api_key"),
    ("腾讯地图 Key", re.compile(r'(?i)(?:qqmap|tencent[_\-]map)[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "api_key"),

    # ── 国内 IM ──
    ("钉钉 AccessToken", re.compile(r'(?i)dingtalk[_\-]?access[_\-]?token\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "token"),
    ("钉钉 Webhook", re.compile(r'https://oapi\.dingtalk\.com/robot/send\?access_token=[A-Za-z0-9]+'), "HIGH", "token"),
    ("企业微信 CorpSecret", re.compile(r'(?i)wecom[_\-]?(?:corp[_\-]?)?secret\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "token"),
    ("企业微信 Webhook", re.compile(r'https://qyapi\.weixin\.qq\.com/cgi-bin/webhook/send\?key=[A-Za-z0-9\-]+'), "HIGH", "token"),
    ("飞书 AppId", re.compile(r'(?i)(?:feishu|lark)[_\-]?app[_\-]?(?:id|key)\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "api_key"),
    ("飞书 AppSecret", re.compile(r'(?i)(?:feishu|lark)[_\-]?app[_\-]?secret\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "api_key"),

    # ── 国内支付 ──
    ("微信支付 Key", re.compile(r'(?i)wechat[_\-]?(?:pay)?[_\-]?(?:key|secret|mch[_\-]?key)\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "payment"),
    ("支付宝 AppId", re.compile(r'(?i)alipay[_\-]?(?:app[_\-]?)?id\s*[=:]\s*["\']?20[0-9]{14,}'), "HIGH", "payment"),
    ("支付宝私钥", re.compile(r'(?i)alipay[_\-]?(?:private[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9+/=]{100,}'), "HIGH", "payment"),

    # ── 国内对象存储 ──
    ("七牛云 AccessKey", re.compile(r'(?i)qiniu[_\-]?(?:access[_\-]?key|secret)\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "cloud"),
    ("又拍云 Operator", re.compile(r'(?i)upyun[_\-]?operator\s*[=:]\s*["\']?[A-Za-z0-9\-_]{10,}'), "HIGH", "cloud"),

    # ── 国内短信 ──
    ("短信服务密码", re.compile(r'(?i)(?:sms|message)[_\-]?(?:password|pwd|secret)\s*[=:]\s*["\']?[^\s"\'<>]{8,}'), "HIGH", "sms"),

    # ═══════════════════════════════════════════
    #  国外云服务
    # ═══════════════════════════════════════════

    # ── AWS ──
    ("AWS Access Key", re.compile(r'(?:A3T[A-Z0-9]|AKIA|AGPA|AIDA|AROA|AIPA|ANPA|ANVA|ASIA)[A-Z0-9]{16}'), "HIGH", "cloud"),
    ("AWS Secret Key", re.compile(r'(?i)aws[_\-]?secret[_\-]?(?:access)?[_\-]?key\s*[=:]\s*["\']?[A-Za-z0-9/+=]{40}'), "HIGH", "cloud"),
    ("AWS Session Token", re.compile(r'(?i)aws[_\-]?session[_\-]?token\s*[=:]\s*["\']?[A-Za-z0-9/+=]{100,}'), "HIGH", "cloud"),
    ("AWS S3 Endpoint", re.compile(r'\.s3\.[a-z0-9-]+\.amazonaws\.com'), "MEDIUM", "cloud"),

    # ── Google Cloud ──
    ("GCP API Key", re.compile(r'AIza[0-9A-Za-z\-_]{35}'), "HIGH", "cloud"),
    ("GCP Service Account", re.compile(r'"type"\s*:\s*"service_account"'), "HIGH", "cloud"),
    ("GCP Private Key", re.compile(r'"private_key"\s*:\s*"-----BEGIN'), "HIGH", "cloud"),
    ("Firebase Database URL", re.compile(r'https://[a-z0-9\-]+\.firebaseio\.com'), "HIGH", "cloud"),
    ("Google Maps Key", re.compile(r'(?i)(?:google[_\-]maps|maps[_\-]api)[_\-]?key\s*[=:]\s*["\']?AIza'), "HIGH", "cloud"),

    # ── Azure ──
    ("Azure Connection String", re.compile(r'(?i)DefaultEndpointsProtocol=https;AccountName=[^;]+;AccountKey=[^;]+'), "HIGH", "cloud"),
    ("Azure Storage Key", re.compile(r'(?i)azure[_\-]?(?:storage)?[_\-]?key\s*[=:]\s*["\']?[A-Za-z0-9+/=]{44,}'), "HIGH", "cloud"),

    # ── GitHub ──
    ("GitHub Token", re.compile(r'gh[pousr]_[A-Za-z0-9_]{36,}'), "HIGH", "token"),
    ("GitHub App Token", re.compile(r'ghu_[A-Za-z0-9]{20,}|ghs_[A-Za-z0-9]{20,}'), "HIGH", "token"),

    # ── AI 服务 ──
    ("OpenAI API Key", re.compile(r'sk-(?:proj-|org-)?[A-Za-z0-9]{20,}'), "HIGH", "api_key"),
    ("Anthropic Key", re.compile(r'(?i)(?:anthropic|claude)[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?sk-ant-[A-Za-z0-9\-_]{20,}'), "HIGH", "api_key"),
    ("HuggingFace Token", re.compile(r'hf_[A-Za-z0-9]{20,}'), "HIGH", "api_key"),
    ("Replicate Token", re.compile(r'r8_[A-Za-z0-9]{14,}'), "HIGH", "api_key"),
    ("Databricks Token", re.compile(r'dapi[a-f0-9]{32}'), "HIGH", "api_key"),
    ("Cohere API Key", re.compile(r'(?i)cohere[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "api_key"),
    ("Mistral API Key", re.compile(r'(?i)mistral[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "api_key"),
    ("Together AI Key", re.compile(r'(?i)together[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "api_key"),
    ("Perplexity API Key", re.compile(r'(?i)perplexity[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "api_key"),
    ("Groq API Key", re.compile(r'(?i)groq[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "api_key"),
    ("DeepSeek API Key", re.compile(r'(?i)deepseek[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?sk-[A-Za-z0-9\-_]{20,}'), "HIGH", "api_key"),

    # ── 云平台 ──
    ("Cloudflare API Key", re.compile(r'(?i)cloudflare[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "cloud"),
    ("Cloudflare Token", re.compile(r'v[A-Za-z0-9]{30,}'), "HIGH", "cloud"),
    ("DigitalOcean Token", re.compile(r'dop_[a-z]_[A-Za-z0-9]{40,}'), "HIGH", "cloud"),
    ("Heroku API Key", re.compile(r'(?i)heroku[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "cloud"),
    ("Supabase Key", re.compile(r'(?i)supabase[_\-]?(?:anon|service)[_\-]?key\s*[=:]\s*["\']?eyJ[A-Za-z0-9\-_]+\.'), "HIGH", "cloud"),
    ("Snowflake Credentials", re.compile(r'(?i)snowflake[_\-]?(?:password|pwd)\s*[=:]\s*["\']?[^\s"\'<>]{8,}'), "HIGH", "cloud"),
    ("Vercel Token", re.compile(r'(?i)vercel[_\-]?(?:token|api[_\-]?key)\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "cloud"),
    ("Netlify Token", re.compile(r'(?i)netlify[_\-]?(?:token|api[_\-]?key)\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "cloud"),
    ("Render API Key", re.compile(r'(?i)render[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "cloud"),
    ("Railway Token", re.compile(r'(?i)railway[_\-]?(?:token|api[_\-]?key)\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "cloud"),

    # ── 对象存储 ──
    ("Backblaze B2 Key", re.compile(r'(?i)(?:backblaze|b2)[_\-]?(?:key|application[_\-]?key)\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "cloud"),
    ("Wasabi Key", re.compile(r'(?i)wasabi[_\-]?(?:access[_\-]?key|secret)\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "cloud"),

    # ── 支付服务 ──
    ("Stripe Key", re.compile(r'(?:sk|pk)_(?:test|live|prod)_[A-Za-z0-9]{20,}'), "HIGH", "payment"),
    ("PayPal Client ID", re.compile(r'(?i)paypal[_\-]?(?:client[_\-]?)?id\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "payment"),
    ("PayPal Secret", re.compile(r'(?i)paypal[_\-]?secret\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "payment"),
    ("Square Token", re.compile(r'(?i)square[_\-]?(?:access[_\-]?token|api[_\-]?key)\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "payment"),

    # ── 邮件服务 ──
    ("Mailgun API Key", re.compile(r'key-[0-9a-f]{32}'), "HIGH", "email"),
    ("SendGrid API Key", re.compile(r'SG\.[A-Za-z0-9\-_]{20,}\.[A-Za-z0-9\-_]{20,}'), "HIGH", "email"),
    ("Postmark API Key", re.compile(r'(?i)postmark[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "email"),
    ("AWS SES Key", re.compile(r'(?i)(?:aws[_\-]?)?ses[_\-]?(?:key|secret)\s*[=:]\s*["\']?[A-Za-z0-9/+=]{20,}'), "HIGH", "email"),

    # ── 短信/推送服务 ──
    ("Twilio Account SID", re.compile(r'AC[a-f0-9]{32}'), "HIGH", "api_key"),
    ("Twilio API Key", re.compile(r'SK[a-f0-9]{32}'), "HIGH", "api_key"),
    ("Vonage API Key", re.compile(r'(?i)vonage[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "api_key"),
    ("Plaid Token", re.compile(r'(?i)plaid[_\-]?(?:token|api[_\-]?key|secret)\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "api_key"),

    # ── 社交/通信 ──
    ("Slack Token", re.compile(r'xox[baprs]-[0-9a-zA-Z-]{10,}'), "HIGH", "token"),
    ("Slack Webhook", re.compile(r'https://hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+'), "HIGH", "token"),
    ("Discord Bot Token", re.compile(r'(?i)discord[_\-]?(?:bot[_\-]?)?token\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "token"),
    ("Telegram Bot Token", re.compile(r'\d{8,10}:[A-Za-z0-9\-_]{30,}'), "HIGH", "token"),
    ("WhatsApp API Key", re.compile(r'(?i)whatsapp[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "token"),

    # ── 监控/日志 ──
    ("Sentry DSN", re.compile(r'https://[a-f0-9]+@sentry\.io/\d+'), "HIGH", "monitoring"),
    ("Datadog API Key", re.compile(r'(?i)datadog[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "monitoring"),
    ("New Relic License Key", re.compile(r'(?i)new[_\-]?relic[_\-]?(?:license[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "monitoring"),
    ("Grafana API Key", re.compile(r'(?i)grafana[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?eyJ[A-Za-z0-9\-_]+\.'), "HIGH", "monitoring"),
    ("Prometheus Basic Auth", re.compile(r'prometheus://[^\s"\'<>]+:[^\s"\'<>]+@'), "HIGH", "monitoring"),

    # ── DNS/域名 ──
    ("Cloudflare DNS Key", re.compile(r'(?i)cloudflare[_\-]?dns[_\-]?(?:key|token)\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "dns"),
    ("Route 53 Key", re.compile(r'(?i)route[_\-]?53[_\-]?(?:key|secret)\s*[=:]\s*["\']?[A-Za-z0-9/+=]{20,}'), "HIGH", "dns"),
    ("GoDaddy API Key", re.compile(r'(?i)godaddy[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "dns"),
    ("Namecheap API Key", re.compile(r'(?i)namecheap[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "dns"),
    ("Cloudflare Registrar Token", re.compile(r'(?i)cloudflare[_\-]?registrar[_\-]?token\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "dns"),

    # ── CDN ──
    ("Akamai Client Token", re.compile(r'(?i)akamai[_\-]?(?:client[_\-]?)?token\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "cdn"),
    ("Fastly API Key", re.compile(r'(?i)fastly[_\-]?(?:api[_\-]?)?key\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "cdn"),

    # ── 容器/CI-CD ──
    ("Docker Registry 密码", re.compile(r'(?i)(?:docker|registry)[_\-]?(?:password|token)\s*[=:]\s*["\']?[^\s"\'<>]{8,}'), "HIGH", "container"),
    ("Jenkins API Token", re.compile(r'(?i)jenkins[_\-]?(?:api[_\-]?)?token\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "cicd"),
    ("CircleCI Token", re.compile(r'(?i)circleci[_\-]?(?:token|api[_\-]?key)\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "cicd"),
    ("GitLab Token", re.compile(r'glpat-[A-Za-z0-9\-_]{20,}'), "HIGH", "token"),
    ("Travis CI Token", re.compile(r'(?i)travis[_\-]?(?:token|api[_\-]?key)\s*[=:]\s*["\']?[A-Za-z0-9\-_]{20,}'), "HIGH", "cicd"),
    ("GitHub Actions Secret", re.compile(r'\$\{\{[^}]*secrets\.[^}]+\}\}'), "LOW", "cicd"),

    # ── Kubernetes ──
    ("Kubernetes Token", re.compile(r'(?i)kubernetes[_\-]?token\s*[=:]\s*["\']?[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+'), "HIGH", "k8s"),
    ("Kubeconfig Password", re.compile(r'(?i)kubeconfig.*password\s*[=:]\s*["\']?[^\s"\'<>]{6,}'), "HIGH", "k8s"),

    # ── 私钥 ──
    ("RSA Private Key", re.compile(r'-----BEGIN\s+(?:RSA\s+)?PRIVATE\s+KEY-----'), "HIGH", "private_key"),
    ("SSH Private Key", re.compile(r'-----BEGIN\s+(?:EC\s+|DSA\s+|OPENSSH\s+)?PRIVATE\s+KEY-----'), "HIGH", "private_key"),
    ("PGP Private Key", re.compile(r'-----BEGIN\s+PGP\s+PRIVATE\s+KEY\s+BLOCK-----'), "HIGH", "private_key"),
    ("PKCS8 Private Key", re.compile(r'-----BEGIN\s+PRIVATE\s+KEY-----'), "HIGH", "private_key"),
    ("PKCS12 证书", re.compile(r'(?i)\.(?:pfx|p12)\b'), "HIGH", "certificate"),

    # ── 证书 ──
    ("SSL/TLS 证书", re.compile(r'-----BEGIN\s+CERTIFICATE-----'), "MEDIUM", "certificate"),

    # ── Terraform / IaC ──
    ("Terraform 明文密码", re.compile(r'(?i)password\s*=\s*"[^"]{6,}"'), "MEDIUM", "iac"),
    ("Pulumi Token", re.compile(r'(?i)pulumi[_\-]?(?:access[_\-]?)?token\s*[=:]\s*["\']?[A-Za-z0-9]{20,}'), "HIGH", "iac"),

    # ═══════════════════════════════════════════
    #  MEDIUM - 疑似敏感信息
    # ═══════════════════════════════════════════

    # ── 通用密钥 ──
    ("Generic API Key", re.compile(r'(?i)(?:api[_\-]?key|apikey)\s*[=:]\s*["\']?[A-Za-z0-9\-_]{16,}'), "MEDIUM", "api_key"),
    ("Generic Secret", re.compile(r'(?i)(?:secret|secret[_\-]?key|app[_\-]?secret)\s*[=:]\s*["\']?[A-Za-z0-9\-_+/=]{16,}'), "MEDIUM", "secret"),
    ("Generic Token", re.compile(r'(?i)(?:access[_\-]?token|auth[_\-]?token|bearer)\s*[=:]\s*["\']?[A-Za-z0-9\-_]{16,}'), "MEDIUM", "token"),
    ("Generic Password", re.compile(r'(?i)(?:password|passwd|pwd)\s*[=:]\s*["\']?[^\s"\'<>]{6,}'), "MEDIUM", "password"),

    # ── JWT ──
    ("JWT Token", re.compile(r'eyJ[A-Za-z0-9\-_]{10,}\.eyJ[A-Za-z0-9\-_]{10,}\.[A-Za-z0-9\-_]{10,}'), "MEDIUM", "token"),

    # ── 加密/签名 ──
    ("Encryption Key", re.compile(r'(?i)(?:encrypt[_\-]?key|cipher[_\-]?key|aes[_\-]?key)\s*[=:]\s*["\']?[A-Za-z0-9+/=]{16,}'), "MEDIUM", "secret"),
    ("Signing Key", re.compile(r'(?i)(?:sign[_\-]?key|hmac[_\-]?key|jwt[_\-]?secret)\s*[=:]\s*["\']?[A-Za-z0-9\-_+/=]{16,}'), "MEDIUM", "secret"),

    # ── 数据库密码 ──
    ("DB Password", re.compile(r'(?i)(?:db[_\-]?password|database[_\-]?password|mysql[_\-]?pwd)\s*[=:]\s*["\']?[^\s"\'<>]{4,}'), "MEDIUM", "database"),

    # ── 邮箱 SMTP ──
    ("SMTP Password", re.compile(r'(?i)smtp[_\-]?password\s*[=:]\s*["\']?[^\s"\'<>]{4,}'), "MEDIUM", "email"),
    ("SMTP Connection", re.compile(r'smtps?://[^\s"\'<>]+:[^\s"\'<>]+@'), "MEDIUM", "email"),

    # ── 通用 Base64 密钥 ──
    ("Base64 Key", re.compile(r'(?i)(?:key|token|secret)\s*[=:]\s*["\']?[A-Za-z0-9+/]{40,}={0,2}["\']?\s*$'), "MEDIUM", "secret"),

    # ── OAuth ──
    ("OAuth Client Secret", re.compile(r'(?i)oauth[_\-]?client[_\-]?secret\s*[=:]\s*["\']?[A-Za-z0-9\-_]{16,}'), "MEDIUM", "token"),

    # ── 消息队列 ──
    ("RabbitMQ 密码", re.compile(r'(?i)(?:rabbitmq|rabbit)[_\-]?password\s*[=:]\s*["\']?[^\s"\'<>]{4,}'), "MEDIUM", "database"),
    ("Kafka SASL 密码", re.compile(r'(?i)(?:kafka|confluent)[_\-]?password\s*[=:]\s*["\']?[^\s"\'<>]{4,}'), "MEDIUM", "database"),

    # ═══════════════════════════════════════════
    #  LOW - 可能误报（疑似提醒）
    # ═══════════════════════════════════════════

    # ── 疑似密码（短密码） ──
    ("疑似密码 (短)", re.compile(r'(?i)(?:password|passwd|pwd)\s*[=:]\s*["\']?[^\s"\'<>]{4,6}["\']?\s*$'), "LOW", "password"),

    # ── 疑似密钥（注释中） ──
    ("疑似密钥 (注释)", re.compile(r'(?i)(?:#|//)\s*(?:password|secret|key|token)\s*[=:]\s*\S+'), "LOW", "comment"),

    # ── 疑似 Token（环境变量） ──
    ("疑似 Token (ENV)", re.compile(r'\$\{?[A-Z_]*(?:KEY|TOKEN|SECRET|PASSWORD)[A-Z_]*\}?'), "LOW", "env"),

    # ── 疑似连接串（无密码） ──
    ("疑似数据库连接", re.compile(r'(?i)(?:mongodb|mysql|postgresql|redis)://[^\s]+'), "LOW", "database"),

    # ── 疑似配置占位符 ──
    ("疑似配置占位符", re.compile(r'(?i)(?:YOUR[_\-]?)?(?:API[_\-]?KEY|SECRET|TOKEN|PASSWORD)\b'), "LOW", "placeholder"),

    # ── 疑似 IP + 端口 ──
    ("疑似内网地址", re.compile(r'(?i)(?:host|server|url)\s*[=:]\s*["\']?(?:10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(?:1[6-9]|2\d|3[01])\.\d+\.\d+)[^\s"\']*'), "LOW", "internal"),

    # ── 疑似邮箱+密码 ──
    ("疑似邮箱凭证", re.compile(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\s*[:;]\s*[A-Za-z0-9]{6,}'), "LOW", "email"),
]

# ─── 白名单 ───────────────────────────────────────────────

IGNORE_PATTERNS = {
    'node_modules', 'vendor', '.git', '__pycache__',
    '.next', '.nuxt', 'dist', 'build', 'target',
    '.idea', '.vscode', '.DS_Store',
}

# 跳过检测脚本自身（避免误报）
IGNORE_FILES = {
    'check_secrets.py', 'pre_push_check.py', 'pre-push-hook',
}

IGNORE_EXTENSIONS = {'.lock', '.min.js', '.min.css', '.map', '.svg', '.png', '.jpg', '.jpeg', '.gif', '.ico', '.woff', '.woff2', '.ttf', '.eot', '.pdf', '.zip', '.tar', '.gz'}

# ─── 假阳性关键词 ───

FALSE_POSITIVE_KEYWORDS = {
    'example', 'test', 'dummy', 'fake', 'placeholder', 'changeme',
    'your-key-here', 'your-secret-here', 'your-token-here',
    'xxx', 'yyy', 'zzz', 'abc123', '123456', 'password123',
}


# ─── 数据结构 ─────────────────────────────────────────────

@dataclass
class Finding:
    file: str
    line_num: int
    line_preview: str
    pattern_name: str
    risk_level: str
    category: str

    def __str__(self):
        icons = {"HIGH": "🔴", "MEDIUM": "🟡", "LOW": "⚪"}
        icon = icons.get(self.risk_level, "❓")
        preview = self.line_preview.strip()[:100]
        return f"  {self.line_num:>4} | [{icon} {self.risk_level}] {self.pattern_name}\n         {preview}"


# ─── 核心逻辑 ─────────────────────────────────────────────

def should_skip(filepath: str) -> bool:
    parts = Path(filepath).parts
    for p in parts:
        if p in IGNORE_PATTERNS:
            return True
    # 跳过检测脚本自身
    if Path(filepath).name in IGNORE_FILES:
        return True
    if Path(filepath).suffix in IGNORE_EXTENSIONS:
        return True
    return False


def scan_line(line: str, filename: str, line_num: int) -> List[Finding]:
    findings = []
    line_lower = line.lower()

    for name, pattern, risk, category in PATTERNS:
        if pattern.search(line):
            # LOW 级别检查假阳性
            if risk == "LOW":
                if any(kw in line_lower for kw in FALSE_POSITIVE_KEYWORDS):
                    continue
            findings.append(Finding(
                file=filename,
                line_num=line_num,
                line_preview=line.rstrip(),
                pattern_name=name,
                risk_level=risk,
                category=category,
            ))
    return findings


def scan_file(filepath: str) -> List[Finding]:
    findings = []
    try:
        with open(filepath, 'r', errors='ignore') as f:
            for i, line in enumerate(f, 1):
                findings.extend(scan_line(line, filepath, i))
    except (PermissionError, IsADirectoryError):
        pass
    return findings


def scan_staged() -> List[Finding]:
    """扫描 git staged 的文件"""
    findings = []
    try:
        import subprocess
        result = subprocess.run(
            ['git', 'diff', '--cached', '--name-only', '--diff-filter=ACM'],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            for filepath in result.stdout.strip().split('\n'):
                filepath = filepath.strip()
                if filepath and not should_skip(filepath) and os.path.isfile(filepath):
                    findings.extend(scan_file(filepath))
    except Exception:
        pass
    return findings


def scan_commits(count: int = 3) -> List[Finding]:
    """扫描最近 N 次提交中新增/修改的文件"""
    findings = []
    try:
        import subprocess
        result = subprocess.run(
            ['git', 'diff', f'HEAD~{count}..HEAD', '--name-only', '--diff-filter=ACM'],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            files = set()
            for line in result.stdout.strip().split('\n'):
                line = line.strip()
                if line and not should_skip(line) and os.path.isfile(line):
                    files.add(line)
            for filepath in files:
                findings.extend(scan_file(filepath))
    except Exception:
        pass
    return findings


def scan_files(filepaths: List[str]) -> List[Finding]:
    """扫描指定文件列表"""
    findings = []
    for filepath in filepaths:
        if not should_skip(filepath) and os.path.isfile(filepath):
            findings.extend(scan_file(filepath))
    return findings


# ─── 输出 ─────────────────────────────────────────────────

def print_report(findings: List[Finding], title: str = ""):
    if title:
        print(f"\n{'─' * 60}")
        print(f"  {title}")
        print(f"{'─' * 60}")

    if not findings:
        print("  ✅ 未发现敏感信息")
        return

    high = [f for f in findings if f.risk_level == "HIGH"]
    medium = [f for f in findings if f.risk_level == "MEDIUM"]
    low = [f for f in findings if f.risk_level == "LOW"]

    # 按类别统计
    categories = {}
    for f in findings:
        cat = f.category
        if cat not in categories:
            categories[cat] = {"HIGH": 0, "MEDIUM": 0, "LOW": 0}
        categories[cat][f.risk_level] += 1

    print(f"\n  ⚠️  发现 {len(findings)} 个潜在敏感信息：")
    print(f"  🔴 HIGH:   {len(high)}")
    print(f"  🟡 MEDIUM: {len(medium)}")
    print(f"  ⚪ LOW:    {len(low)}")
    print()

    # 按类别汇总
    if categories:
        cat_names = {
            "pii": "个人信息 (PII)", "cloud": "云服务密钥", "token": "Token",
            "api_key": "API Key", "database": "数据库/缓存/消息队列", "private_key": "私钥",
            "payment": "支付服务", "email": "邮件服务", "secret": "通用密钥",
            "password": "密码", "iac": "基础设施代码", "container": "容器/CI-CD",
            "k8s": "Kubernetes", "certificate": "证书", "comment": "注释",
            "env": "环境变量", "placeholder": "配置占位符", "internal": "内网地址",
            "sms": "短信服务", "monitoring": "监控/日志", "dns": "DNS/域名",
            "cdn": "CDN", "cicd": "CI/CD",
        }
        for cat, counts in sorted(categories.items(), key=lambda x: sum(x[1].values()), reverse=True):
            name = cat_names.get(cat, cat)
            total = sum(counts.values())
            print(f"    • {name}: {total} 项")
        print()

    # 详细列表
    current_file = None
    for f in findings:
        if f.file != current_file:
            print(f"  📁 {f.file}")
            current_file = f.file
        print(f"      {f}")

    print()
    if low:
        print("  💡 LOW 级别为疑似提醒，请人工确认是否为真实敏感信息。")
        print("     常见误报：示例代码、测试数据、占位符。")


# ─── 主函数 ───────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description='扫描代码中的敏感信息')
    parser.add_argument('files', nargs='*', help='要扫描的文件')
    parser.add_argument('--staged', action='store_true', help='扫描 git staged 文件')
    parser.add_argument('--commits', type=int, default=0, help='扫描最近 N 次提交')
    parser.add_argument('--json', action='store_true', help='JSON 格式输出')
    parser.add_argument('--all', action='store_true', help='显示所有级别（包括 LOW）')
    parser.add_argument('--min-risk', choices=['HIGH', 'MEDIUM', 'LOW'], default='MEDIUM',
                        help='最低风险等级 (默认: MEDIUM)')
    args = parser.parse_args()

    findings = []

    if args.staged:
        findings.extend(scan_staged())
    if args.commits > 0:
        findings.extend(scan_commits(args.commits))
    if args.files:
        findings.extend(scan_files(args.files))

    # 如果没有任何参数，扫描当前目录
    if not args.staged and args.commits == 0 and not args.files:
        for root, dirs, files in os.walk('.'):
            dirs[:] = [d for d in dirs if d not in IGNORE_PATTERNS]
            for f in files:
                filepath = os.path.join(root, f)
                if not should_skip(filepath):
                    findings.extend(scan_file(filepath))

    # 过滤风险等级
    risk_order = {'HIGH': 0, 'MEDIUM': 1, 'LOW': 2}
    min_risk = risk_order.get(args.min_risk, 1)
    filtered = [f for f in findings if risk_order.get(f.risk_level, 99) <= min_risk]

    # 输出
    if args.json:
        import json
        print(json.dumps([{
            'file': f.file,
            'line': f.line_num,
            'preview': f.line_preview[:100],
            'pattern': f.pattern_name,
            'risk': f.risk_level,
            'category': f.category,
        } for f in filtered], indent=2, ensure_ascii=False))
    else:
        title = f"扫描结果"
        if args.staged:
            title = "Git Staged 文件扫描"
        elif args.commits > 0:
            title = f"最近 {args.commits} 次提交扫描"
        print_report(filtered, title)

    # 退出码：只根据过滤后的结果决定
    sys.exit(1 if filtered else 0)


if __name__ == '__main__':
    main()
