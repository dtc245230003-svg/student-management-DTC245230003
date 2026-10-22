const router = require('express').Router();
const pool = require('../db');

router.param('id', (req, res, next, id) => {
  if (/^\d+$/.test(id)) return next();
  res.status(404).render('error', { title: 'Không tìm thấy', message: 'Mã không hợp lệ.' });
});

function validate(b) {
  const data = {
    student_id: (b.student_id || '').trim(),
    subject: (b.subject || '').trim(),
    score: (b.score || '').trim().replace(',', '.')
  };
  const errors = [];
  if (!/^\d+$/.test(data.student_id)) errors.push('Vui lòng chọn sinh viên.');
  if (data.subject.length < 2 || data.subject.length > 100) errors.push('Tên môn học phải từ 2 đến 100 ký tự.');
  const n = Number(data.score);
  if (data.score === '' || !Number.isFinite(n) || n < 0 || n > 10) errors.push('Điểm phải là số từ 0 đến 10.');
  return { errors, data };
}

async function render(res, status, title, item, errors, action) {
  const [students] = await pool.execute('SELECT id, student_code, full_name FROM students ORDER BY student_code');
  res.status(status).render('grades/form', { title, item, errors, action, students });
}

function dbErrorMessage(e) {
  if (e.code === 'ER_DUP_ENTRY') return 'Sinh viên này đã có điểm môn đó. Hãy sửa điểm cũ.';
  if (e.code === 'ER_NO_REFERENCED_ROW_2') return 'Sinh viên được chọn không tồn tại.';
  return null;
}

router.get('/', async (req, res, next) => {
  try {
    const [rows] = await pool.execute(
      `SELECT g.id, s.student_code, s.full_name, g.subject, g.score
       FROM grades g JOIN students s ON s.id = g.student_id
       ORDER BY s.student_code, g.subject`);
    res.render('grades/list', { title: 'Điểm số', rows, msg: req.query.msg || null, err: req.query.err || null });
  } catch (e) { next(e); }
});

router.get('/new', async (req, res, next) => {
  try { await render(res, 200, 'Thêm điểm', {}, [], '/grades'); } catch (e) { next(e); }
});

router.post('/', async (req, res, next) => {
  try {
    const { errors, data } = validate(req.body);
    if (errors.length) return await render(res, 400, 'Thêm điểm', data, errors, '/grades');
    try {
      await pool.execute('INSERT INTO grades (student_id, subject, score) VALUES (?, ?, ?)',
        [data.student_id, data.subject, Number(data.score).toFixed(2)]);
      res.redirect('/grades?msg=' + encodeURIComponent('Đã thêm điểm'));
    } catch (e) {
      const m = dbErrorMessage(e);
      if (!m) throw e;
      await render(res, 400, 'Thêm điểm', data, [m], '/grades');
    }
  } catch (e) { next(e); }
});

router.get('/:id/edit', async (req, res, next) => {
  try {
    const [rows] = await pool.execute('SELECT * FROM grades WHERE id = ?', [req.params.id]);
    if (!rows.length) return next();
    await render(res, 200, 'Sửa điểm', rows[0], [], `/grades/${req.params.id}/update`);
  } catch (e) { next(e); }
});

router.post('/:id/update', async (req, res, next) => {
  try {
    const action = `/grades/${req.params.id}/update`;
    const { errors, data } = validate(req.body);
    if (errors.length) return await render(res, 400, 'Sửa điểm', data, errors, action);
    try {
      await pool.execute('UPDATE grades SET student_id = ?, subject = ?, score = ? WHERE id = ?',
        [data.student_id, data.subject, Number(data.score).toFixed(2), req.params.id]);
      res.redirect('/grades?msg=' + encodeURIComponent('Đã cập nhật điểm'));
    } catch (e) {
      const m = dbErrorMessage(e);
      if (!m) throw e;
      await render(res, 400, 'Sửa điểm', data, [m], action);
    }
  } catch (e) { next(e); }
});

router.post('/:id/delete', async (req, res, next) => {
  try {
    await pool.execute('DELETE FROM grades WHERE id = ?', [req.params.id]);
    res.redirect('/grades?msg=' + encodeURIComponent('Đã xóa điểm'));
  } catch (e) { next(e); }
});

module.exports = router;
