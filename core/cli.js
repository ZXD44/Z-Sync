const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const prompts = require('prompts');

const PROJECTS_DIR = path.join(__dirname, '..', 'projects');
const pkg = require('../package.json');

// ดักจับ Ctrl+C ไม่ให้มันแสดงข้อความน่ารำคาญของ Windows
process.on('SIGINT', () => {
    console.log('\n\n 👋 [Z-Sync] ปิดระบบเรียบร้อยแล้ว ไว้เจอกันใหม่ครับ!\n');
    process.exit(0);
});

async function main() {
    console.clear();
    console.log('==========================================');
    console.log(`  💎 Z-Sync v${pkg.version} - ระบบจัดการโปรเจกต์`);
    console.log('==========================================\n');

    // ดึงรายชื่อโปรเจกต์ที่มีอยู่
    let existingProjects = [];
    if (fs.existsSync(PROJECTS_DIR)) {
        existingProjects = fs.readdirSync(PROJECTS_DIR).filter(f => {
            return fs.statSync(path.join(PROJECTS_DIR, f)).isDirectory();
        });
    }

    const choices = existingProjects.map(p => ({ title: `📁 ${p}`, value: p }));
    choices.push({ title: '✨ สร้างโปรเจกต์ใหม่...', value: '__NEW__' });
    choices.push({ title: '🚪 ออกจากระบบ', value: '__EXIT__' });

    const response = await prompts({
        type: 'select',
        name: 'project',
        message: 'เลือกโปรเจกต์ที่ต้องการเปิด:',
        choices: choices,
        initial: 0,
        hint: '- ใช้ลูกศร (ขึ้น/ลง) เพื่อเลือก, กด Enter เพื่อตกลง'
    });

    if (!response.project || response.project === '__EXIT__') {
        console.log('\n 👋 [Z-Sync] ปิดระบบเรียบร้อยแล้ว\n');
        process.exit(0);
    }

    let selectedProject = response.project;

    if (selectedProject === '__NEW__') {
        const newProj = await prompts({
            type: 'text',
            name: 'name',
            message: 'ระบุชื่อโปรเจกต์ใหม่:',
            validate: value => value.length > 0 ? true : 'ห้ามเว้นว่างเด็ดขาด!'
        });
        
        if (!newProj.name) {
            console.log('\n 👋 [Z-Sync] ยกเลิกการสร้างโปรเจกต์\n');
            process.exit(0);
        }
        selectedProject = newProj.name;
    }

    console.log(`\n 🚀 กำลังเตรียมเซิร์ฟเวอร์สำหรับโปรเจกต์: ${selectedProject}...\n`);

    // เคลียร์ Port 3000
    try {
        require('child_process').execSync('for /f "tokens=5" %a in (\'netstat -aon ^| findstr :3000\') do taskkill /f /pid %a >nul 2>&1');
    } catch(e) {}

    // 1. ล้างปลั๊กอินเก่าๆ ออกให้หมดเพื่อป้องกันบัค
    const pluginsRoot = path.join(process.env.LOCALAPPDATA, 'Roblox', 'Plugins');
    const oldFolders = ['AIBridge', 'ZXD44', 'Z-Sync'];
    
    oldFolders.forEach(folder => {
        const oldPath = path.join(pluginsRoot, folder);
        if (fs.existsSync(oldPath)) {
            try {
                fs.rmSync(oldPath, { recursive: true, force: true });
            } catch(e) {
                console.log(`  [!] ไม่สามารถลบโฟลเดอร์เก่า ${folder} ได้ (อาจเปิด Studio ค้างไว้)`);
            }
        }
    });

    // 2. ติดตั้งปลั๊กอินเวอร์ชันล่าสุดแบบสะอาดเอี่ยม
    const pluginDir = path.join(pluginsRoot, 'Z-Sync');
    if (!fs.existsSync(pluginDir)) {
        fs.mkdirSync(pluginDir, { recursive: true });
    }
    const pluginSource = path.join(__dirname, '..', 'studio', 'plugin.lua');
    const pluginDest = path.join(pluginDir, 'init.server.lua');
    
    // อ่านโค้ดปลั๊กอินมาแก้ไขเลขเวอร์ชันก่อนบันทึก
    let pluginCode = fs.readFileSync(pluginSource, 'utf-8');
    pluginCode = pluginCode.replace(/v\d+\.\d+\.\d+/g, `v${pkg.version}`);
    
    fs.writeFileSync(pluginDest, pluginCode);
    console.log(`  [OK] ติดตั้งปลั๊กอิน Z-Sync v${pkg.version} เรียบร้อยแล้ว`);

    // รัน main.js
    const serverProcess = spawn('node', [path.join(__dirname, 'main.js'), selectedProject], {
        stdio: 'inherit'
    });

    serverProcess.on('close', (code) => {
        console.log(`\n [INFO] เซิร์ฟเวอร์ปิดตัวลง (รหัส: ${code})\n`);
        process.exit(code);
    });
}

main().catch(err => {
    console.error('[!] Error:', err.message);
    process.exit(1);
});
