SET NAMES utf8mb4;

CREATE TABLE classes (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  class_code  VARCHAR(20)  NOT NULL,
  class_name  VARCHAR(100) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_class_code (class_code)
) ENGINE=InnoDB;

CREATE TABLE students (
  id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  student_code  VARCHAR(20)  NOT NULL,
  full_name     VARCHAR(100) NOT NULL,
  email         VARCHAR(100) NOT NULL,
  class_id      INT UNSIGNED NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_student_code (student_code),
  UNIQUE KEY uq_student_email (email),
  CONSTRAINT fk_students_class FOREIGN KEY (class_id)
    REFERENCES classes (id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE grades (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  student_id  INT UNSIGNED NOT NULL,
  subject     VARCHAR(100) NOT NULL,
  score       DECIMAL(4,2) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_student_subject (student_id, subject),
  CONSTRAINT fk_grades_student FOREIGN KEY (student_id)
    REFERENCES students (id) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT chk_score CHECK (score >= 0 AND score <= 10)
) ENGINE=InnoDB;

INSERT INTO classes (class_code, class_name) VALUES
  ('CNTT01', 'Công nghệ thông tin 01'),
  ('CNTT02', 'Công nghệ thông tin 02'),
  ('KTPM01', 'Kỹ thuật phần mềm 01');

INSERT INTO students (student_code, full_name, email, class_id) VALUES
  ('SV001', 'Nguyễn Văn An',  'an.nv@example.com',   1),
  ('SV002', 'Trần Thị Bình',  'binh.tt@example.com', 1),
  ('SV003', 'Lê Hoàng Cường', 'cuong.lh@example.com', 1),
  ('SV004', 'Phạm Minh Dũng', 'dung.pm@example.com', 2),
  ('SV005', 'Vũ Thị Hà',      'ha.vt@example.com',   2),
  ('SV006', 'Đỗ Quang Huy',   'huy.dq@example.com',  3),
  ('SV007', 'Bùi Thu Lan',    'lan.bt@example.com',  3),
  ('SV008', 'Hoàng Gia Nam',  'nam.hg@example.com',  3);

INSERT INTO grades (student_id, subject, score) VALUES
  (1, 'Cơ sở dữ liệu', 8.50), (1, 'Mạng máy tính', 7.00),
  (2, 'Cơ sở dữ liệu', 9.00), (2, 'Mạng máy tính', 8.25),
  (3, 'Cơ sở dữ liệu', 6.50),
  (4, 'Lập trình Web', 7.75), (5, 'Lập trình Web', 8.00),
  (6, 'Công nghệ phần mềm', 9.25), (7, 'Công nghệ phần mềm', 7.50),
  (8, 'Công nghệ phần mềm', 5.50);
