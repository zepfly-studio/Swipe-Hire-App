// Single source of truth for the pick-lists the app shows when a candidate
// fills in a profile (role, skills, degree, city) and that the resume parser
// matches against. The app fetches them with GET /taxonomy.
//
// NOTE: this is a realistic stand-in. The exact lists will be replaced by the
// website's shared/taxonomy.js (ROLES 195, SKILLS 206, DEGREES 47, CITIES 183,
// STATES 36, LOCATIONS 219) once it is copied over; keep the export names and
// the ordering rules (30 major cities first, "Remote" last) when you do.

const ROLES = [
  // Software and IT
  "Web Developer", "Full Stack Developer", "Frontend Developer", "Backend Developer", "Android Developer",
  "iOS Developer", "Flutter Developer", "React Native Developer", "Mobile App Developer", "Software Engineer",
  "Software Developer", "Senior Software Engineer", "Java Developer", "Python Developer", "PHP Developer",
  "Node.js Developer", "React Developer", "Angular Developer", "Vue.js Developer", "WordPress Developer",
  ".NET Developer", "C++ Developer", "Golang Developer", "Ruby on Rails Developer", "Django Developer",
  "Laravel Developer", "Shopify Developer", "Game Developer", "Embedded Engineer", "Firmware Engineer",
  "DevOps Engineer", "Cloud Engineer", "Site Reliability Engineer", "System Administrator", "Network Engineer",
  "Cyber Security Analyst", "Ethical Hacker", "QA Engineer", "Manual Tester", "Automation Tester",
  "Test Engineer", "Database Administrator", "Data Engineer", "Data Analyst", "Data Scientist",
  "Business Intelligence Analyst", "Machine Learning Engineer", "AI Engineer", "Prompt Engineer", "Business Analyst",
  "Technical Support Engineer", "IT Support Executive", "Help Desk Executive", "Technical Writer", "Solution Architect",
  "Technical Lead", "Engineering Manager", "Product Manager", "Product Owner", "Project Manager",
  "Scrum Master", "Program Manager", "CTO",
  // Design and creative
  "UI/UX Designer", "UI Designer", "UX Researcher", "Graphic Designer", "Product Designer",
  "Web Designer", "Motion Graphics Designer", "Video Editor", "Animator", "3D Artist",
  "Illustrator", "Photographer", "Videographer", "Creative Director", "Art Director",
  "Fashion Designer", "Interior Designer", "Architect", "Content Writer", "Copywriter",
  "Content Creator", "Social Media Manager", "Social Media Executive", "Journalist", "Editor",
  "Translator", "Voice Over Artist", "Podcast Producer",
  // Marketing and sales
  "Digital Marketing Executive", "Digital Marketing Manager", "SEO Executive", "SEO Specialist", "Performance Marketer",
  "Content Marketing Manager", "Email Marketing Specialist", "Brand Manager", "Marketing Manager", "Marketing Executive",
  "Growth Hacker", "Influencer Marketing Manager", "Public Relations Executive", "Market Research Analyst", "Sales Executive",
  "Sales Manager", "Business Development Executive", "Business Development Manager", "Inside Sales Executive", "Field Sales Executive",
  "Area Sales Manager", "Key Account Manager", "Account Executive", "Pre-Sales Consultant", "Telecaller",
  "Tele Sales Executive", "Customer Success Manager", "Relationship Manager", "Real Estate Agent", "Insurance Advisor",
  // Operations, support and admin
  "Customer Support Executive", "Customer Care Executive", "Call Center Agent", "BPO Executive", "Chat Support Executive",
  "Operations Executive", "Operations Manager", "Supply Chain Manager", "Logistics Executive", "Warehouse Executive",
  "Procurement Executive", "Store Manager", "Office Administrator", "Office Assistant", "Receptionist",
  "Front Desk Executive", "Data Entry Operator", "Back Office Executive", "Executive Assistant", "Personal Assistant",
  "Team Leader", "Quality Analyst", "Quality Control Inspector", "Process Associate", "Delivery Executive",
  "Driver", "Security Guard", "Facility Manager", "Housekeeping Supervisor",
  // HR and finance
  "HR Executive", "HR Manager", "HR Generalist", "HR Recruiter", "Talent Acquisition Specialist",
  "Recruitment Consultant", "Payroll Executive", "Training and Development Manager", "Accountant", "Senior Accountant",
  "Accounts Executive", "Accounts Manager", "Chartered Accountant", "Company Secretary", "Auditor",
  "Tax Consultant", "GST Executive", "Financial Analyst", "Investment Banker", "Credit Analyst",
  "Loan Officer", "Bank Clerk", "Banking Executive", "Finance Manager", "Cashier",
  "Legal Advisor", "Lawyer", "Paralegal", "Compliance Officer",
  // Engineering and technical
  "Mechanical Engineer", "Civil Engineer", "Electrical Engineer", "Electronics Engineer", "Production Engineer",
  "Maintenance Engineer", "Site Engineer", "Quality Engineer", "Design Engineer", "CAD Designer",
  "Automobile Engineer", "Chemical Engineer", "Industrial Engineer", "Electrician", "Technician",
  "Mechanic", "Welder", "Machine Operator", "CNC Operator", "Plumber",
  // Healthcare, education and others
  "Doctor", "Nurse", "Pharmacist", "Lab Technician", "Physiotherapist",
  "Medical Representative", "Teacher", "Lecturer", "Professor", "School Principal",
  "Academic Counsellor", "Admission Counsellor", "Tutor", "Education Counsellor", "Hotel Manager",
  "Chef", "Cook", "Waiter", "Travel Consultant", "Event Manager",
  "Fitness Trainer", "Beautician", "Retail Sales Associate", "Cashier / Billing Executive", "Fresher / Intern",
  "Intern",
];

const SKILLS = [
  // Web and programming
  "HTML", "CSS", "JavaScript", "TypeScript", "React", "React Native", "Angular", "Vue.js", "Next.js", "Node.js",
  "Express.js", "jQuery", "Bootstrap", "Tailwind CSS", "Sass", "Redux", "GraphQL", "REST API", "Webpack", "WordPress",
  "PHP", "Laravel", "Python", "Django", "Flask", "FastAPI", "Java", "Spring Boot", "Kotlin", "Swift",
  "Flutter", "Dart", "C", "C++", "C#", ".NET", "ASP.NET", "Go", "Rust", "Ruby",
  "Ruby on Rails", "Scala", "R", "MATLAB", "Shell Scripting", "Bash", "Android", "iOS", "Firebase", "Unity",
  // Data and cloud
  "SQL", "MySQL", "PostgreSQL", "MongoDB", "Redis", "Oracle", "SQLite", "Elasticsearch", "Power BI", "Tableau",
  "Excel", "Advanced Excel", "Google Sheets", "Data Analysis", "Data Visualization", "Data Mining", "Statistics", "Machine Learning", "Deep Learning", "TensorFlow",
  "PyTorch", "Pandas", "NumPy", "Scikit-learn", "NLP", "Computer Vision", "Big Data", "Hadoop", "Spark", "ETL",
  "AWS", "Azure", "Google Cloud", "Docker", "Kubernetes", "Terraform", "Jenkins", "CI/CD", "Git", "GitHub",
  "Linux", "Networking", "Cyber Security", "Penetration Testing", "Selenium", "Manual Testing", "Automation Testing", "JIRA", "Postman", "Agile",
  // Design and creative
  "Figma", "Adobe XD", "Sketch", "Photoshop", "Illustrator", "InDesign", "After Effects", "Premiere Pro", "Final Cut Pro", "Canva",
  "CorelDRAW", "Blender", "AutoCAD", "SolidWorks", "3D Modeling", "UI Design", "UX Design", "Wireframing", "Prototyping", "Video Editing",
  "Photography", "Animation", "Typography", "Branding", "Logo Design",
  // Marketing and sales
  "SEO", "SEM", "Google Ads", "Facebook Ads", "Social Media Marketing", "Digital Marketing", "Email Marketing", "Content Writing", "Copywriting", "Content Marketing",
  "Google Analytics", "Affiliate Marketing", "Influencer Marketing", "Market Research", "Lead Generation", "Cold Calling", "Sales", "B2B Sales", "B2C Sales", "Negotiation",
  "CRM", "Salesforce", "HubSpot", "Zoho", "Customer Support", "Customer Service", "Telecalling", "Business Development", "Account Management", "Client Handling",
  // Finance, accounts and operations
  "Tally", "Tally Prime", "GST", "Taxation", "TDS", "Accounting", "Bookkeeping", "Accounts Payable", "Accounts Receivable", "Financial Reporting",
  "Financial Modeling", "Budgeting", "Auditing", "Payroll", "SAP", "QuickBooks", "Banking", "Insurance", "Loan Processing", "Data Entry",
  "MS Office", "MS Word", "MS PowerPoint", "Typing", "Inventory Management", "Supply Chain", "Logistics", "Procurement", "Vendor Management", "Operations Management",
  // HR and management
  "Recruitment", "Talent Acquisition", "Onboarding", "Employee Engagement", "HR Policies", "Performance Management", "Training", "Payroll Processing", "Project Management", "Product Management",
  "Team Management", "Leadership", "People Management", "Strategic Planning", "Process Improvement", "Six Sigma", "Quality Assurance", "Risk Management", "Compliance", "Stakeholder Management",
  // Soft skills and languages
  "Communication", "Teamwork", "Problem Solving", "Time Management", "Critical Thinking", "Public Speaking", "Presentation", "Adaptability", "Creativity", "Analytical Skills",
  "English", "Hindi", "Marathi", "Gujarati", "Punjabi", "Tamil", "Telugu", "Kannada", "Malayalam", "Bengali",
  "Urdu", "Odia", "Assamese",
];

const DEGREES = [
  "10th", "12th (Science)", "12th (Commerce)", "12th (Arts)", "12th",
  "ITI", "Diploma (Engineering)", "Diploma (Polytechnic)", "Diploma",
  "B.Tech", "B.Tech (CSE)", "B.Tech (IT)", "B.Tech (ECE)", "B.Tech (Mechanical)", "B.Tech (Civil)", "B.Tech (Electrical)",
  "B.E.", "BCA", "B.Sc", "B.Sc (Hons)", "B.Sc (IT)", "B.Sc (Computer Science)", "B.Com", "B.Com (Hons)", "BBA", "BA", "B.Des", "B.Pharm", "B.Arch", "LLB", "MBBS", "BHM",
  "M.Tech", "M.E.", "MCA", "M.Sc", "M.Com", "MBA", "PGDM", "MA", "M.Des", "LLM", "M.Pharm",
  "CA", "CS", "CMA", "PhD",
];

// The 30 largest first (the picker shows these before the alphabetical rest).
const MAJOR_CITIES = [
  "Jaipur", "Delhi", "New Delhi", "Mumbai", "Bengaluru", "Hyderabad", "Pune", "Chennai", "Kolkata", "Ahmedabad",
  "Gurugram", "Noida", "Ghaziabad", "Faridabad", "Chandigarh", "Lucknow", "Indore", "Bhopal", "Nagpur", "Surat",
  "Vadodara", "Kochi", "Coimbatore", "Visakhapatnam", "Patna", "Kanpur", "Thane", "Navi Mumbai", "Nashik", "Bhubaneswar",
];

const OTHER_CITIES = [
  "Agartala", "Agra", "Ajmer", "Akola", "Aligarh", "Allahabad", "Alwar", "Ambala", "Amravati", "Amritsar",
  "Anantapur", "Aurangabad", "Bareilly", "Bathinda", "Belgaum", "Bellary", "Bhagalpur", "Bharatpur", "Bhavnagar",
  "Bhilai", "Bhilwara", "Bhiwadi", "Bikaner", "Bilaspur", "Bokaro", "Chandrapur", "Cuttack", "Darbhanga", "Davanagere",
  "Dehradun", "Dhanbad", "Dharwad", "Durgapur", "Erode", "Firozabad", "Gandhinagar", "Gaya", "Gorakhpur", "Guntur",
  "Guwahati", "Gwalior", "Haldwani", "Hapur", "Haridwar", "Hisar", "Hosur", "Hubballi", "Imphal", "Jabalpur",
  "Jalandhar", "Jalgaon", "Jammu", "Jamnagar", "Jamshedpur", "Jhansi", "Jodhpur", "Junagadh", "Kakinada", "Kannur",
  "Karnal", "Kharagpur", "Kolhapur", "Kollam", "Kota", "Kozhikode", "Kurnool", "Latur", "Ludhiana", "Madurai",
  "Malappuram", "Mangaluru", "Mathura", "Meerut", "Moradabad", "Mysuru", "Nanded", "Nellore", "Panipat", "Panaji",
  "Pimpri-Chinchwad", "Pondicherry", "Prayagraj", "Raipur", "Rajkot", "Rajahmundry", "Ranchi", "Rewari", "Rohtak", "Roorkee",
  "Rourkela", "Saharanpur", "Salem", "Sambalpur", "Sangli", "Shillong", "Shimla", "Siliguri", "Solapur",
  "Sonipat", "Srinagar", "Thanjavur", "Thiruvananthapuram", "Thrissur", "Tiruchirappalli", "Tirunelveli", "Tirupati", "Udaipur", "Ujjain",
  "Vapi", "Varanasi", "Vasai-Virar", "Vellore", "Vijayawada", "Warangal",
  "Ballari", "Bhadrak", "Bhiwani", "Bulandshahr", "Chittoor", "Dhule", "Etawah", "Hazaribagh", "Hoshiarpur", "Karimnagar",
  "Khammam", "Mohali", "Muzaffarpur", "Nizamabad", "Palakkad", "Patiala", "Ratlam", "Satna", "Silchar",
  "Tiruppur", "Tumakuru", "Yamunanagar",
];

// Older spellings people still type; kept so profiles and resumes written
// with them still match.
const LEGACY_CITIES = ["Bangalore", "Gurgaon", "Bombay", "Calcutta", "Madras", "Poona", "Trivandrum", "Mysore", "Baroda", "Cochin", "Vizag", "Pondicherry (Puducherry)"];

const STATES = [
  "Andhra Pradesh", "Arunachal Pradesh", "Assam", "Bihar", "Chhattisgarh", "Goa", "Gujarat", "Haryana", "Himachal Pradesh",
  "Jharkhand", "Karnataka", "Kerala", "Madhya Pradesh", "Maharashtra", "Manipur", "Meghalaya", "Mizoram", "Nagaland",
  "Odisha", "Punjab", "Rajasthan", "Sikkim", "Tamil Nadu", "Telangana", "Tripura", "Uttar Pradesh", "Uttarakhand", "West Bengal",
  "Andaman and Nicobar Islands", "Chandigarh UT", "Dadra and Nagar Haveli and Daman and Diu", "Delhi NCR", "Jammu and Kashmir",
  "Ladakh", "Lakshadweep", "Puducherry",
];

const REMOTE = "Remote";

// Major cities first, then everything else alphabetically, then legacy
// spellings, and "Remote" always last.
const CITIES = [
  ...MAJOR_CITIES,
  ...[...OTHER_CITIES].sort((a, b) => a.localeCompare(b)),
  ...LEGACY_CITIES,
  REMOTE,
];

// Location autocomplete: cities, then states, then Remote.
const LOCATIONS = [...MAJOR_CITIES, ...[...OTHER_CITIES].sort((a, b) => a.localeCompare(b)), ...STATES, REMOTE];

// Option lists that are enums rather than pick-lists (shared with validation).
const WORK_MODES = ["onsite", "remote", "hybrid"];
const JOB_TYPES = ["full-time", "part-time", "internship", "contract"];
const QUALIFICATIONS = ["10th", "12th", "Diploma", "Graduate", "Post Graduate", "PhD"];
const GENDERS = ["Male", "Female", "Other"];
const NOTICE_PERIODS = ["Immediate", "15 days", "30 days", "60 days", "90 days"];

function taxonomy() {
  return { roles: ROLES, skills: SKILLS, degrees: DEGREES, cities: CITIES, states: STATES, locations: LOCATIONS };
}

module.exports = {
  ROLES,
  SKILLS,
  DEGREES,
  CITIES,
  STATES,
  LOCATIONS,
  MAJOR_CITIES,
  WORK_MODES,
  JOB_TYPES,
  QUALIFICATIONS,
  GENDERS,
  NOTICE_PERIODS,
  taxonomy,
};
