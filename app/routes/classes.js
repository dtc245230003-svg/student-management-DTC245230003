const router = require('express').Router();
const pool = require('../db');

router.param('id', (req, res, next, id) => {
  if (/^\d+$/.test(id)) return next();
  res.status(404).render('error', { title: 'Không tìm thấy', message: 'Mã không hợp lệ.' });
});

function validate(b) {
  const data = { class_code: (b.class_code || '').trim(), class_name: (b.class_name || '').trim() };
  const errors = [];
  if (!/^[A-Za-z0-9_-]{2,20}$/.test(data.class_code)) errors.push('Mã lớp gồm 2–20 ký tự: chữ, số, gạch ngang hoặc gạch dưới.');
  if (data.class_name.length < 2 || data.class_name.length > 100) errors.push('Tên lớp phải từ 2 đến 100 ký tự.');
  return { errors, data };
}
const form = (res, status, title, item, errors, action) =>
  res.status(status).render('classes/form', { title, item, errors, action });

router.get('/', async (req, res, next) => {
  try {
    const [rows] = await pool.execute(
      `SELECT c.id, c.class_code, c.class_name, COUNT(s.id) AS student_count
       FROM classes c LEFT JOIN students s ON s.class_id = c.id
       GROUP BY c.id ORDER BY c.class_code`);
    res.render('classes/list', { title: 'Lớp học', rows, msg: req.query.msg || null, err: req.query.err || null });
  } catch (e) { next(e); }
});

router.get('/new', (req, res) => form(res, 200, 'Thêm lớp', {}, [], '/classes'));

router.post('/', async (req, res, next) => {
  const { errors, data } = validate(req.body);
  if (errors.length) return form(res, 400, 'Thêm lớp', data, errors, '/classes');
  try {
    await pool.execute('INSERT INTO classes (class_code, class_name) VALUES (?, ?)', [data.class_code, data.class_name]);
    res.redirect('/classes?msg=' + encodeURIComponent('Đã thêm lớp ' + data.class_code));
  } catch (e) {
    if (e.code === 'ER_DUP_ENTRY') return form(res, 400, 'Thêm lớp', data, ['Mã lớp đã tồn tại.'], '/classes');
    next(e);
  }
});

router.get('/:id/edit', async (req, res, next) => {
  try {
    const [rows] = await pool.execute('SELECT * FROM classes WHERE id = ?', [req.params.id]);
    if (!rows.length) return next();
    form(res, 200, 'Sửa lớp', rows[0], [], `/classes/${req.params.id}/update`);
  } catch (e) { next(e); }
});

router.post('/:id/update', async (req, res, next) => {
  const action = `/classes/${req.params.id}/update`;
  const { errors, data } = validate(req.body);
  if (errors.length) return form(res, 400, 'Sửa lớp', data, errors, action);
  try {
    await pool.execute('UPDATE classes SET class_code = ?, class_name = ? WHERE id = ?', [data.class_code, data.class_name, req.params.id]);
    res.redirect('/classes?msg=' + encodeURIComponent('Đã cập nhật lớp ' + data.class_code));
  } catch (e) {
    if (e.code === 'ER_DUP_ENTRY') return form(res, 400, 'Sửa lớp', data, ['Mã lớp đã tồn tại.'], action);
    next(e);
  }
});

router.post('/:id/delete', async (req, res, next) => {
  try {
    await pool.execute('DELETE FROM classes WHERE id = ?', [req.params.id]);
    res.redirect('/classes?msg=' + encodeURIComponent('Đã xóa lớp'));
  } catch (e) {
    if (e.code === 'ER_ROW_IS_REFERENCED_2') {
      return res.redirect('/classes?err=' + encodeURIComponent('Không thể xóa: lớp này vẫn còn sinh viên. Hãy chuyển hoặc xóa sinh viên trước.'));
    }
    next(e);
  }
});

module.exports = router;
