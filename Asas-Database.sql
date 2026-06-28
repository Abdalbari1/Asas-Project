/*
=========================================================================================================
                                دليل التنفيذ والربط مع بيئة (.NET Core)
                                (بنية Multi-tenant SaaS المعزولة)
=========================================================================================================

🌟 القاعدة الذهبية في هذا النظام: "العازل هو كود الباك-إند وليس الـ SQL"

بما أن النظام يخدم عدة شركات في نفس قاعدة البيانات، فإننا لا نعتمد على قيود SQL المعقدة لمنع تسرب البيانات،
بل نعتمد على ميزة (Global Query Filter) داخل الـ Entity Framework Core في الباك-إند.

🛠️ خطوات التنفيذ في .NET Core:
1. قم بتنفيذ هذا السكربت في SQL Server لبناء الجداول.
2. في مشروع الـ .NET، قم بإنشاء كلاس (AppDbContext) يمثل قاعدة البيانات.
3. داخل دالة (OnModelCreating) في الـ DbContext، ستقوم بكتابة كود العزل التالي مرة واحدة فقط:
   
   protected override void OnModelCreating(ModelBuilder modelBuilder)
   {
       // جلب رقم الشركة للمستخدم الحالي (من التوكن أو الجلسة)
       int currentComId = _tenantService.GetCurrentCompanyId();

       // تطبيق جدار العزل الأوتوماتيكي على جميع الجداول:
       modelBuilder.Entity<Departments>().HasQueryFilter(d => d.Com_id == currentComId);
       modelBuilder.Entity<AddEmp>().HasQueryFilter(e => e.Com_id == currentComId);
       modelBuilder.Entity<Employees>().HasQueryFilter(u => u.Com_id == currentComId);
       modelBuilder.Entity<Tasks>().HasQueryFilter(t => t.Com_id == currentComId);
       modelBuilder.Entity<InternalMessages>().HasQueryFilter(m => m.Com_id == currentComId);
   }
   
اي استعلام او ادخال او حذف يرسل رقم الشركه تلقائي لا حاجه لكتابتها كل شوي بمعنى انها أوتوماتيكياً   Controllers سيحقن ال 


=========================================================================================================
*/

-- 📌 توجيه محرك SQL للعمل على قاعدة بيانات SKY
Use SKY;


--------------------------------------------------------------------------
-- 🏢 1. جدول الشركات (المستأجرين للنظام)
--------------------------------------------------------------------------
Create table Company(
    -- المعرف التلقائي للشركة، يبدأ من 1000 ويزيد 203، وهو المفتاح الأساسي
    Com_id INT IDENTITY(1000,203) PRIMARY KEY,
    -- حالة الشركة (1 = مفعلة، 0 = موقوفة بسبب عدم السداد مثلاً)
    IsActive BIT NOT NULL,
    -- سعر اشتراك الشركة (الحد الأقصى 4 خانات)
    Price DECIMAL(4) NOT NULL DEFAULT 0,
    -- تاريخ انتهاء صلاحية الاشتراك
    Date_of_end DATETIME NOT NULL
);

--------------------------------------------------------------------------
-- 🛠️ 2. جدول البلاغات والمشاكل (للدعم الفني)
--------------------------------------------------------------------------
Create table Issue(
    -- المعرف التلقائي للبلاغ
    Id INT IDENTITY(1,1) PRIMARY KEY,
    -- اسم صاحب المشكلة (يدعم الحروف العربية بفضل nVarchar)
    Name nVarchar(50) NOT NULL,
    -- البريد للتواصل معه
    Email VARCHAR(100),
    -- نص المشكلة التفصيلي
    Message nVARCHAR(255)
);

--------------------------------------------------------------------------
-- 📁 3. جدول الأقسام
--------------------------------------------------------------------------
Create Table Departments(
    -- رقم الشركة (جسر العزل)
    Com_id INT NOT NULL,
    -- المعرف التلقائي للقسم
    Dep_auto_id INT IDENTITY(1,1) primary key,
    -- اسم القسم
    Dep_name nVARCHAR(100) NOT NULL,
    -- معرف المشرف (مربوط برقم الموظف التلقائي لاحقاً)
    Supervisor_id INT NULL,
    
    -- قيد يمنع إنشاء قسمين بنفس الاسم داخل نفس الشركة
    CONSTRAINT UQ_Dep_name_Com_id UNIQUE (Dep_name, Com_id),
    -- ربط القسم بالشركة
    CONSTRAINT FK_Company_to_Departments FOREIGN KEY (Com_id) REFERENCES Company(Com_id)
);
-- فهرس لتسريع جلب أقسام الشركة المحددة في الباك-إند
CREATE INDEX IX_Departments_Com_id ON Departments(Com_id);

--------------------------------------------------------------------------
-- 👨‍💼 4. جدول إضافة الموظفين (البيانات الإدارية)
--------------------------------------------------------------------------
Create Table AddEmp(
    -- المعرف التلقائي والوحيد للموظف (المفتاح الأساسي)
    Emp_auto_id int IDENTITY(1,1),
    -- رقم الشركة لزوم العزل
    Com_id INT NOT NULL,
    -- الرقم الوظيفي اليدوي المعطى من الشركة (مثل 1001)
    Emp_id VARCHAR(50) NOT NULL,
    -- الصلاحية الوظيفية (تترجم كـ Enum في الـ C#)
    Role DECIMAL(5) NOT NULL,
    -- رقم القسم التابع له الموظف
    Dep_auto_id INT NOT NULL,
    -- المسمى الوظيفي
    Job_title VARCHAR(100) NOT NULL,
    
    -- تعريف المفتاح الأساسي
    primary key(Emp_auto_id),
    -- ربط الموظف بالشركة (مع تفعيل التحديث والحذف التلقائي)
    CONSTRAINT FK_Company_to_AddEmp FOREIGN KEY (Com_id) REFERENCES Company(Com_id) ON UPDATE CASCADE ON DELETE CASCADE,
    -- ربط الموظف بالقسم (تم الاكتفاء بالـ Update Cascade لمنع تعارض مسارات الحذف 1785)
    constraint FK_Departments_to_AddEmp FOREIGN KEY (Dep_auto_id) REFERENCES Departments(Dep_auto_id) ON UPDATE CASCADE,

    -- قيد يمنع تكرار الرقم الوظيفي اليدوي داخل الشركة الواحدة
    CONSTRAINT UQ_Emp_id_Com_id UNIQUE (Emp_id, Com_id)
);
-- فهرس لتسريع فلترة الموظفين
CREATE INDEX IX_AddEmp_Com_id ON AddEmp(Com_id);

--------------------------------------------------------------------------
-- 🔐 5. جدول حسابات الموظفين (بيانات الدخول والتفعيل)
--------------------------------------------------------------------------
Create Table Employees(
    -- المعرف التلقائي لجدول الحسابات
    Employee_id INT IDENTITY(1,1) PRIMARY KEY,
    -- رقم الشركة
    Com_id INT NOT NULL,
    -- الربط رأس برأس مع بيانات الموظف الإدارية
    Emp_auto_id INT NOT NULL,
    -- الاسم الكامل للموظف
    Name nVARCHAR(255) NOT NULL,
    -- البريد الإلكتروني (يستخدم لتسجيل الدخول)
    Email VARCHAR(255) NOT NULL,
    -- كلمة المرور المشفرة
    Hashing_Password VARCHAR(255) NOT NULL,
    -- رقم الجوال
    Phone_Number VARCHAR(30) NOT NULL,
    -- حالة الحساب (هل قام بالتفعيل أم لا)
    IsActive BIT NOT NULL DEFAULT 0,
    -- التخصص العلمي
    Major nVARCHAR(100) NOT NULL,
    
    -- ربط الحساب بالشركة (بدون Cascade لمنع تضارب الحذف مع جدول الإضافة)
    constraint FK_Company_to_Employees FOREIGN KEY (Com_id) REFERENCES Company(Com_id),
    -- إذا تم حذف الموظف من جدول الإدارة، يُحذف حسابه تلقائياً
    CONSTRAINT FK_AddEmp_to_Employees FOREIGN KEY (Emp_auto_id) REFERENCES AddEmp(Emp_auto_id) ON UPDATE CASCADE ON DELETE CASCADE,
    -- منع تكرار الإيميل ورقم الهاتف داخل الشركة
    CONSTRAINT UQ_Email_Com_id_Phone_Number UNIQUE (Email, Com_id, Phone_Number),
    -- ضمان حساب واحد فقط لكل موظف (العلاقة 1-to-1)
    CONSTRAINT UQ_Emp_auto_id UNIQUE (Emp_auto_id)
);
-- فهرس لتسريع عمليات تسجيل الدخول Authorization
CREATE INDEX IX_Employees_Com_id ON Employees(Com_id);

--------------------------------------------------------------------------
-- 📋 6. جدول المهام
--------------------------------------------------------------------------
Create Table Tasks(
    -- المعرف التلقائي للمهمة
    Task_id INT IDENTITY(1,1) PRIMARY KEY,
    -- الشركة التابعة لها المهمة
    Com_id INT NOT NULL,
    -- الموظف المستلم للمهمة
    Emp_auto_id INT NOT NULL,
    -- القسم التابعة له المهمة
    Dep_auto_id INT NOT NULL,
    -- المشرف المسؤول عن المهمة
    Supervisor_id INT NULL,
    -- عنوان المهمة
    Task_name nVARCHAR(50) NOT NULL,
    -- التفاصيل الكاملة للمهمة
    Task_details nVARCHAR(MAX) NOT NULL,
    -- أولوية المهمة (عالية، متوسطة، منخفضة)
    Task_priority DECIMAL(3) NOT NULL,
    -- تاريخ البدء
    Date_of_start DATE NOT NULL,
    -- تاريخ الانتهاء المتوقع
    Date_of_end DATE NOT NULL,
    -- تاريخ الانتهاء الفعلي
    Completion_date DATE,
    -- حالة المهمة الحالية
    status nVARCHAR(50) NOT NULL,

    -- الربط بالشركة (بدون Cascade لمنع المشكلة 1785)
    CONSTRAINT FK_Company_to_Tasks FOREIGN KEY (Com_id) REFERENCES Company(Com_id),
    -- الربط بالموظف 
    CONSTRAINT FK_AddEmp_to_Tasks FOREIGN KEY (Emp_auto_id) REFERENCES AddEmp(Emp_auto_id),
    -- الربط بالقسم (تمت إزالة الفاصلة الزائدة من هنا لكي يعمل الكود)
    CONSTRAINT FK_Departments_to_Tasks FOREIGN KEY (Dep_auto_id) REFERENCES Departments(Dep_auto_id)
);
-- فهرس لتسريع عرض المهام للشركة الحالية
CREATE INDEX IX_Tasks_Com_id ON Tasks(Com_id);

------------------------------------------------------------------------------------------------------------------------------
-- ✉️ 7. جدول الرسائل الأساسية (أصل الرسالة)
------------------------------------------------------------------------------------------------------------------------------
CREATE TABLE InternalMessages (
    -- المعرف التلقائي للرسالة
    Msg_id INT IDENTITY(1,1) PRIMARY KEY,
    -- لزوم العزل في الباك-إند
    Com_id INT NOT NULL,                        
    -- رقم الموظف المُرسِل
    Sender_id INT NOT NULL,                     
    -- رقم الرسالة الأب (يستخدم في حال كانت الرسالة الحالية عبارة عن "رد")
    Parent_msg_id INT NULL,                     
    -- موضوع الرسالة
    Subject nVARCHAR(255) NULL,                  
    -- نص الرسالة التفصيلي
    Body nVARCHAR(MAX) NOT NULL,                
    -- وقت إنشاء الرسالة (يأخذ وقت السيرفر تلقائياً)
    CreatedAt DATETIME NOT NULL DEFAULT GETDATE(),

    -- الروابط الأجنبية
    CONSTRAINT FK_Company_to_InternalMessages FOREIGN KEY (Com_id) REFERENCES Company(Com_id),
    CONSTRAINT FK_AddEmp_to_InternalMessages FOREIGN KEY (Sender_id) REFERENCES AddEmp(Emp_auto_id),
    -- علاقة ذاتية لربط الردود بالرسالة الأصلية
    CONSTRAINT FK_InternalMessages_to_InternalMessages FOREIGN KEY (Parent_msg_id) REFERENCES InternalMessages(Msg_id) 
);
CREATE INDEX IX_InternalMessages_Com_id ON InternalMessages(Com_id);

------------------------------------------------------------------------------------------------------------------------------
-- 👥 8. جدول المستلمين (صندوق الوارد)
------------------------------------------------------------------------------------------------------------------------------
CREATE TABLE MessageRecipients (
    -- رقم الرسالة
    Msg_id INT NOT NULL,
    -- الموظف المستلم
    Recipient_id INT NOT NULL,                  
    -- مؤشر القراءة (0 = غير مقروء، 1 = مقروء)
    IsRead BIT NOT NULL DEFAULT 0,              
    -- وقت فتح الرسالة
    ReadAt DATETIME NULL,                       

    -- مفتاح مركب لمنع إرسال الرسالة لنفس الشخص مرتين عن طريق الخطأ
    PRIMARY KEY (Msg_id, Recipient_id),         
    
    -- إذا حذفت الرسالة من النظام، تُحذف من صناديق الوارد للمستلمين
    CONSTRAINT FK_InternalMessages_to_MessageRecipients FOREIGN KEY (Msg_id) REFERENCES InternalMessages(Msg_id) ON DELETE CASCADE,
    CONSTRAINT FK_AddEmp_to_MessageRecipients FOREIGN KEY (Recipient_id) REFERENCES AddEmp(Emp_auto_id)
);

------------------------------------------------------------------------------------------------------------------------------
-- 📎 9. جدول المرفقات (الصور والملفات)
------------------------------------------------------------------------------------------------------------------------------
CREATE TABLE MessageAttachments (
    -- المعرف التلقائي للمرفق
    Attachment_id INT IDENTITY(1,1) PRIMARY KEY,
    -- رقم الرسالة التابع لها
    Msg_id INT NOT NULL,
    -- مسار حفظ الملف في السيرفر (مثال: /wwwroot/uploads/file.pdf)
    FilePath VARCHAR(500) NOT NULL,             
    -- نوع الملف
    FileType VARCHAR(50) NOT NULL,              
    -- اسم الملف الظاهر للمستخدمين
    FileName nVARCHAR(255) NOT NULL,             
    -- وقت الرفع
    UploadedAt DATETIME NOT NULL DEFAULT GETDATE(),

    -- إذا تم حذف الرسالة، يتم حذف سجلات مرفقاتها تلقائياً
    CONSTRAINT FK_InternalMessages_to_MessageAttachments FOREIGN KEY (Msg_id) REFERENCES InternalMessages(Msg_id) ON DELETE CASCADE
);
------------------------------------------------------------------------------