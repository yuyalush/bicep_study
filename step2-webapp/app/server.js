const express = require('express');
const app = express();

// Bicep の appSettings で設定した環境変数を読み込む
const PORT = process.env.PORT || 3000;
const ENVIRONMENT = process.env.ENVIRONMENT || 'local';
const NODE_ENV = process.env.NODE_ENV || 'development';

// ルート: メインページ
app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html lang="ja">
    <head>
      <meta charset="UTF-8">
      <title>Bicep Step2 App</title>
      <style>
        body { font-family: sans-serif; max-width: 600px; margin: 60px auto; padding: 0 20px; }
        .badge { display: inline-block; padding: 4px 12px; border-radius: 4px;
                 background: #0078d4; color: white; font-size: 14px; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        td, th { border: 1px solid #ddd; padding: 8px 12px; text-align: left; }
        th { background: #f4f4f4; }
      </style>
    </head>
    <body>
      <h1>Bicep Step2 Web App</h1>
      <p>Azure App Service へのデプロイが成功しました！</p>
      <p>環境: <span class="badge">${ENVIRONMENT}</span></p>
      <h2>アプリ設定（環境変数）</h2>
      <table>
        <tr><th>変数名</th><th>値</th><th>設定元</th></tr>
        <tr><td>ENVIRONMENT</td><td>${ENVIRONMENT}</td><td>Bicep appSettings</td></tr>
        <tr><td>NODE_ENV</td><td>${NODE_ENV}</td><td>Bicep appSettings</td></tr>
        <tr><td>PORT</td><td>${PORT}</td><td>App Service (自動付与)</td></tr>
      </table>
      <p style="margin-top:30px; color:#888; font-size:13px;">
        GET /health でヘルスチェックエンドポイントも確認できます。
      </p>
    </body>
    </html>
  `);
});

// ヘルスチェックエンドポイント
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    environment: ENVIRONMENT,
    nodeEnv: NODE_ENV,
    timestamp: new Date().toISOString()
  });
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT} [${ENVIRONMENT}]`);
});
