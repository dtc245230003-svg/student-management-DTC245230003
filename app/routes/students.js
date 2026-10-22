const router = require('express').Router();
const pool = require('../db');

router.param('id', (req, res, next, id) => {
  if (/^\d+$/.test(id)) return next();
  res.status(404).render('error', { title: 'Không tìm thấy', message: 'Mã không hợp lệ.' });
});

function validate(b) {
  const data = {
    student_code: (b.student_code || '').trim(),
    full_name: (b.full_name || '').trim(),
    email: (b.email || '').trim(),
    class_id: (b.class_id || '').trim()
  };
  const errors = [];
  if (!/^[A-Za-z0-9]{3,20}$/.test(data.student_code)) errors.push('Mã sinh viên gồm 3–20 ký tự chữ hoặc số.');
  if (data.full_name.length < 2 || data.full_name.length > 100) errors.push('Họ tên phải từ 2 đến 100 ký tự.');
  if (data.email.length > 100 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(data.email)) errors.push('Email không hợp lệ.');
  if (!/^\d+$/.test(data.class_id)) errors.push('Vui lòng chọn lớp.');
  return { errors, data };
}

async function render(res, status, title, item, errors, action) {
  const [classes] = await pool.execute('SELECT id, class_code, class_name FROM classes ORDER BY class_code');
  res.status(status).render('students/form', { title, item, errors, action, classes });
}

function dbErrorMessage(e) {
  if (e.code === 'ER_DUP_ENTRY') return 'Mã sinh viên hoặc email đã tồn tại.';
  if (e.code === 'ER_NO_REFERENCED_ROW_2') return 'Lớp được chọn không tồn tại.';
  return null;
}

router.get('/', async (req, res, next) => {
  try {
    const [rows] = await pool.execute(
      `SELECT s.id, s.student_code, s.full_name, s.email, c.class_code
       FROM students s JOIN classes c ON c.id = s.class_id
       ORDER BY s.student_code`);
    res.render('students/list', { title: 'Sinh viên', rows, msg: req.query.msg || null, err: req.query.err || null });
  } catch (e) { next(e); }
});

router.get('/new', async (req, res, next) => {
  try { await render(res, 200, 'Thêm sinh viên', {}, [], '/students'); } catch (e) { next(e); }
});

router.post('/', async (req, res, next) => {
  try {
    const { errors, data } = validate(req.body);
    if (errors.length) return await render(res, 400, 'Thêm sinh viên', data, errors, '/students');
    try {
      await pool.execute('INSERT INTO students (student_code, full_name, email, class_id) VALUES (?, ?, ?, ?)',
        [data.student_code, data.full_name, data.email, data.class_id]);
      res.redirect('/students?msg=' + encodeURIComponent('Đã thêm sinh viên ' + data.student_code));
    } catch (e) {
      const m = dbErrorMessage(e);
      if (!m) throw e;
      await render(res, 400, 'Thêm sinh viên', data, [m], '/students');
    }
  } catch (e) { next(e); }
});

router.get('/:id/edit', async (req, res, next) => {
  try {
    const [rows] = await pool.execute('SELECT * FROM students WHERE id = ?', [req.params.id]);
    if (!rows.length) return next();
    await render(res, 200, 'Sửa sinh viên', rows[0], [], `/students/${req.params.id}/update`);
  } catch (e) { next(e); }
});

router.post('/:id/update', async (req, res, next) => {
  try {
    const action = `/students/${req.params.id}/update`;
    const { errors, data } = validate(req.body);
    if (errors.length) return await render(res, 400, 'Sửa sinh viên', data, errors, action);
    try {
      await pool.execute('UPDATE students SET student_code = ?, full_name = ?, email = ?, class_id = ? WHERE id = ?',
        [data.student_code, data.full_name, data.email, data.class_id, req.params.id]);
      res.redirect('/students?msg=' + encodeURIComponent('Đã cập nhật sinh viên ' + data.student_code));
    } catch (e) {
      const m = dbErrorMessage(e);
      if (!m) throw e;
      await render(res, 400, 'Sửa sinh viên', data, [m], action);
    }
  } catch (e) { next(e); }
});

router.post('/:id/delete', async (req, res, next) => {
  try {
    // Điểm của sinh viên bị xóa theo (ON DELETE CASCADE)
    await pool.execute('DELETE FROM students WHERE id = ?', [req.params.id]);
    res.redirect('/students?msg=' + encodeURIComponent('Đã xóa sinh viên và điểm liên quan'));
  } catch (e) { next(e); }
});

module.exports = router;
