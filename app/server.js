const express = require('express');
const path = require('path');
const pool = require('./db');

const app = express();
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.set('trust proxy', 1);
app.disable('x-powered-by');

app.use(express.urlencoded({ extended: false }));
app.use(express.static(path.join(__dirname, 'public')));

// Log mỗi request ra stdout (Promtail/Loki sẽ thu thập ở Giai đoạn 4b)
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    if (req.path === '/health') return;
    console.log(`${new Date().toISOString()} ${req.method} ${req.originalUrl} ${res.statusCode} ${Date.now() - start}ms`);
  });
  next();
});

app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok' });
  } catch (e) {
    console.error('Health check lỗi DB:', e.message);
    res.status(503).json({ status: 'db_error' });
  }
});

app.get('/', async (req, res, next) => {
  try {
    const [[c]] = await pool.query('SELECT COUNT(*) AS n FROM classes');
    const [[s]] = await pool.query('SELECT COUNT(*) AS n FROM students');
    const [[g]] = await pool.query('SELECT COUNT(*) AS n, ROUND(AVG(score), 2) AS avg FROM grades');
    res.render('index', { title: 'Tổng quan', classes: c.n, students: s.n, grades: g.n, avg: g.avg });
  } catch (e) { next(e); }
});

app.use('/classes', require('./routes/classes'));
app.use('/students', require('./routes/students'));
app.use('/grades', require('./routes/grades'));

app.use((req, res) => {
  res.status(404).render('error', { title: 'Không tìm thấy', message: 'Trang bạn tìm không tồn tại.' });
});

app.use((err, req, res, next) => {
  console.error('LỖI:', err);
  res.status(500).render('error', { title: 'Lỗi máy chủ', message: 'Đã có lỗi xảy ra. Vui lòng thử lại sau.' });
});

app.listen(3000, '0.0.0.0', () => console.log('Student app đang chạy ở cổng 3000'));
