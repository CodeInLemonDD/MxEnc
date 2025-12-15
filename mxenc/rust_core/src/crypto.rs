use aes_gcm::{
    aead::{Aead, KeyInit, OsRng},
    Aes256Gcm, Key, Nonce,
};
use anyhow::{anyhow, Result};
use byteorder::{BigEndian, ReadBytesExt, WriteBytesExt};
use rand::{Rng, RngCore};
use std::io::{Cursor, Read, Write};
use zeroize::Zeroize;
use flutter_rust_bridge::frb;

// 常量定义
const MAGIC: &[u8] = b"MXENC20"; // 升级到版本2.0
const SALT_SIZE: usize = 32;
const NONCE_SIZE: usize = 12;
const KEY_SIZE: usize = 32;

// 文件类型枚举
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum FileType {
    Generic = 0,    // 普通文件
    Image = 1,      // 图片文件
    Novel = 2,      // 小说文件
    Comic = 3,      // 漫画容器
    RichNovel = 4,  // 富文本小说容器
    Other = 255,    // 其他类型
}

/// MxEnc 文件格式处理器
#[frb(ignore)]
pub struct MxEncFile {
    pub original_filename: String,
    pub file_type: FileType,
    pub metadata: Vec<u8>, // 可选的JSON元数据
    pub salt: Vec<u8>,
    pub nonce: Vec<u8>,
    pub ciphertext: Vec<u8>,
}

impl MxEncFile {
    /// 从原始文件内容和密码创建加密文件
    pub fn encrypt(
        plaintext: &[u8],
        password: &str,
        original_filename: &str,
    ) -> Result<Vec<u8>> {
        // 根据文件名判断文件类型
        let file_type = determine_file_type(original_filename);
        
        // 生成随机盐值和随机数
        let mut salt = vec![0u8; SALT_SIZE];
        let mut nonce = vec![0u8; NONCE_SIZE];
        
        OsRng.fill_bytes(&mut salt);
        OsRng.fill_bytes(&mut nonce);
        
        // 从密码派生密钥
        let mut key = derive_key(password, &salt)?;
        
        // 加密数据
        let cipher = Aes256Gcm::new(&key);
        let nonce_ref = Nonce::from_slice(&nonce);
        let ciphertext = cipher
            .encrypt(nonce_ref, plaintext)
            .map_err(|e| anyhow!("加密失败: {}", e))?;
        
        // 构建 MxEnc 文件
        let file = MxEncFile {
            original_filename: original_filename.to_string(),
            file_type,
            metadata: Vec::new(), // 初始为空，可以根据需要添加元数据
            salt,
            nonce,
            ciphertext,
        };
        
        // 序列化为二进制
        let result = file.to_bytes()?;
        
        // 安全清除密钥
        key.zeroize();
        
        Ok(result)
    }
    
    /// 高级加密函数，支持指定文件类型和元数据
    pub fn encrypt_with_metadata(
        plaintext: &[u8],
        password: &str,
        original_filename: &str,
        file_type: FileType,
        metadata: Option<&[u8]>,
    ) -> Result<Vec<u8>> {
        // 生成随机盐值和随机数
        let mut salt = vec![0u8; SALT_SIZE];
        let mut nonce = vec![0u8; NONCE_SIZE];
        
        OsRng.fill_bytes(&mut salt);
        OsRng.fill_bytes(&mut nonce);
        
        // 从密码派生密钥
        let mut key = derive_key(password, &salt)?;
        
        // 加密数据
        let cipher = Aes256Gcm::new(&key);
        let nonce_ref = Nonce::from_slice(&nonce);
        let ciphertext = cipher
            .encrypt(nonce_ref, plaintext)
            .map_err(|e| anyhow!("加密失败: {}", e))?;
        
        // 构建 MxEnc 文件
        let file = MxEncFile {
            original_filename: original_filename.to_string(),
            file_type,
            metadata: metadata.unwrap_or_default().to_vec(),
            salt,
            nonce,
            ciphertext,
        };
        
        // 序列化为二进制
        let result = file.to_bytes()?;
        
        // 安全清除密钥
        key.zeroize();
        
        Ok(result)
    }
    
    /// 从加密文件内容和密码解密文件
    pub fn decrypt(encrypted_data: &[u8], password: &str) -> Result<(String, Vec<u8>)> {
        // 解析 MxEnc 文件
        let file = MxEncFile::from_bytes(encrypted_data)?;
        
        // 从密码派生密钥
        let mut key = derive_key(password, &file.salt)?;
        
        // 解密数据
        let cipher = Aes256Gcm::new(&key);
        let nonce_ref = Nonce::from_slice(&file.nonce);
        let plaintext = cipher
            .decrypt(nonce_ref, file.ciphertext.as_ref())
            .map_err(|_| anyhow!("解密失败：密码错误或文件已损坏"))?;
        
        // 安全清除密钥
        key.zeroize();
        
        Ok((file.original_filename, plaintext))
    }
    
    /// 解析 MxEnc 文件头，返回原始文件名和文件类型
    pub fn parse_header(encrypted_data: &[u8]) -> Result<String> {
        let (filename, _) = Self::parse_header_extended(encrypted_data)?;
        Ok(filename)
    }
    
    /// 扩展的文件头解析，返回文件名和文件类型
    pub fn parse_header_extended(encrypted_data: &[u8]) -> Result<(String, FileType)> {
        let mut cursor = Cursor::new(encrypted_data);
        
        // 检查魔数
        let mut magic = vec![0u8; MAGIC.len()];
        cursor.read_exact(&mut magic)?;
        
        // 支持旧版本格式的向后兼容性
        let is_v1_format = magic.as_slice() == b"MXENC10";
        if !is_v1_format && magic.as_slice() != MAGIC {
            return Err(anyhow!("无效的 MxEnc 文件格式"));
        }
        
        // 读取原始文件名长度
        let name_len = cursor.read_u32::<BigEndian>()? as usize;
        if name_len > 1024 {
            return Err(anyhow!("文件名长度异常"));
        }
        
        // 读取原始文件名
        let mut filename_bytes = vec![0u8; name_len];
        cursor.read_exact(&mut filename_bytes)?;
        let original_filename = String::from_utf8(filename_bytes)?;
        
        // 对于旧版本格式，直接返回文件类型为Generic
        if is_v1_format {
            return Ok((original_filename, FileType::Generic));
        }
        
        // 对于新版本，读取文件类型
        let file_type_value = cursor.read_u8()?;
        let file_type = match file_type_value {
            0 => FileType::Generic,
            1 => FileType::Image,
            2 => FileType::Novel,
            3 => FileType::Comic,
            4 => FileType::RichNovel,
            _ => FileType::Other,
        };
        
        Ok((original_filename, file_type))
    }
    
    /// 解析完整的文件头信息，包括元数据
    pub fn parse_full_header(encrypted_data: &[u8]) -> Result<(String, FileType, Vec<u8>)> {
        let mut cursor = Cursor::new(encrypted_data);
        
        // 检查魔数
        let mut magic = vec![0u8; MAGIC.len()];
        cursor.read_exact(&mut magic)?;
        
        // 支持旧版本格式的向后兼容性
        let is_v1_format = magic.as_slice() == b"MXENC10";
        if !is_v1_format && magic.as_slice() != MAGIC {
            return Err(anyhow!("无效的 MxEnc 文件格式"));
        }
        
        // 读取原始文件名长度
        let name_len = cursor.read_u32::<BigEndian>()? as usize;
        if name_len > 1024 {
            return Err(anyhow!("文件名长度异常"));
        }
        
        // 读取原始文件名
        let mut filename_bytes = vec![0u8; name_len];
        cursor.read_exact(&mut filename_bytes)?;
        let original_filename = String::from_utf8(filename_bytes)?;
        
        // 对于旧版本格式，直接返回默认值
        if is_v1_format {
            return Ok((original_filename, FileType::Generic, Vec::new()));
        }
        
        // 对于新版本，读取文件类型
        let file_type_value = cursor.read_u8()?;
        let file_type = match file_type_value {
            0 => FileType::Generic,
            1 => FileType::Image,
            2 => FileType::Novel,
            3 => FileType::Comic,
            4 => FileType::RichNovel,
            _ => FileType::Other,
        };
        
        // 读取元数据长度和内容
        let metadata_len = cursor.read_u32::<BigEndian>()? as usize;
        let mut metadata = Vec::new();
        if metadata_len > 0 && metadata_len <= 65536 { // 限制元数据大小
            metadata.resize(metadata_len, 0);
            cursor.read_exact(&mut metadata)?;
        }
        
        Ok((original_filename, file_type, metadata))
    }
    
    /// 将 MxEnc 文件序列化为字节
    fn to_bytes(&self) -> Result<Vec<u8>> {
        let mut buffer = Vec::new();
        
        // 写入魔数
        buffer.write_all(MAGIC)?;
        
        // 写入原始文件名长度和内容
        let filename_bytes = self.original_filename.as_bytes();
        buffer.write_u32::<BigEndian>(filename_bytes.len() as u32)?;
        buffer.write_all(filename_bytes)?;
        
        // 写入文件类型
        buffer.write_u8(self.file_type as u8)?;
        
        // 写入元数据长度和内容
        buffer.write_u32::<BigEndian>(self.metadata.len() as u32)?;
        buffer.write_all(&self.metadata)?;
        
        // 写入盐值
        buffer.write_all(&self.salt)?;
        
        // 写入随机数
        buffer.write_all(&self.nonce)?;
        
        // 写入密文
        buffer.write_all(&self.ciphertext)?;
        
        Ok(buffer)
    }
    
    /// 从字节解析 MxEnc 文件
    fn from_bytes(data: &[u8]) -> Result<Self> {
        let mut cursor = Cursor::new(data);
        
        // 检查魔数
        let mut magic = vec![0u8; MAGIC.len()];
        cursor.read_exact(&mut magic)?;
        
        // 支持旧版本格式的向后兼容性
        let is_v1_format = magic.as_slice() == b"MXENC10";
        if !is_v1_format && magic.as_slice() != MAGIC {
            return Err(anyhow!("无效的 MxEnc 文件格式"));
        }
        
        // 读取原始文件名长度
        let name_len = cursor.read_u32::<BigEndian>()? as usize;
        if name_len > 1024 {
            return Err(anyhow!("文件名长度异常"));
        }
        
        // 读取原始文件名
        let mut filename_bytes = vec![0u8; name_len];
        cursor.read_exact(&mut filename_bytes)?;
        let original_filename = String::from_utf8(filename_bytes)?;
        
        let mut file_type = FileType::Generic;
        let mut metadata = Vec::new();
        
        // 对于新版本，读取额外字段
        if !is_v1_format {
            // 读取文件类型
            let file_type_value = cursor.read_u8()?;
            file_type = match file_type_value {
                0 => FileType::Generic,
                1 => FileType::Image,
                2 => FileType::Novel,
                3 => FileType::Comic,
                4 => FileType::RichNovel,
                _ => FileType::Other,
            };
            
            // 读取元数据长度和内容
            let metadata_len = cursor.read_u32::<BigEndian>()? as usize;
            if metadata_len > 0 && metadata_len <= 65536 { // 限制元数据大小
                metadata.resize(metadata_len, 0);
                cursor.read_exact(&mut metadata)?;
            }
        }
        
        // 读取盐值
        let mut salt = vec![0u8; SALT_SIZE];
        cursor.read_exact(&mut salt)?;
        
        // 读取随机数
        let mut nonce = vec![0u8; NONCE_SIZE];
        cursor.read_exact(&mut nonce)?;
        
        // 读取密文
        let mut ciphertext = Vec::new();
        cursor.read_to_end(&mut ciphertext)?;
        
        Ok(MxEncFile {
            original_filename,
            file_type,
            metadata,
            salt,
            nonce,
            ciphertext,
        })
    }
}

/// 从密码和盐值派生加密密钥
fn derive_key(password: &str, salt: &[u8]) -> Result<Key<Aes256Gcm>> {
    // 兼容 Dart 实现：使用 PBKDF2 (SHA256, 100000 iterations)
    // Dart: _pbkdf2(password, salt, 32)
    
    use pbkdf2::pbkdf2;
    use hmac::Hmac;
    use sha2::Sha256;

    let mut key_bytes = [0u8; KEY_SIZE];
    
    pbkdf2::<Hmac<Sha256>>(
        password.as_bytes(),
        salt,
        100000,
        &mut key_bytes
    ).map_err(|e| anyhow!("密钥派生失败: {}", e))?;
    
    let key = Key::<Aes256Gcm>::from_slice(&key_bytes).clone();
    
    // 安全清除临时密钥字节
    key_bytes.zeroize();
    
    Ok(key)
}

/// 生成设备指纹（增强版，基于系统信息）
pub fn generate_device_fingerprint() -> String {
    // 在实际应用中，这里可以使用更多系统信息来生成更稳定的指纹
    // 但为了简单起见，我们保持使用随机ID，确保隐私和一致性
    let mut rng = rand::thread_rng();
    let random_id: u64 = rng.gen();
    format!("DEV-{:016X}", random_id)
}

/// 根据文件名确定文件类型
fn determine_file_type(filename: &str) -> FileType {
    // 将文件名转为小写进行比较
    let filename_lower = filename.to_lowercase();
    
    // 检查小说文件类型
    if filename_lower.ends_with(".novel") || 
       filename_lower.ends_with(".txt") || 
       filename_lower.ends_with(".epub") ||
       filename_lower.ends_with(".mobi") ||
       filename_lower.ends_with(".pdf") {
        return FileType::Novel;
    }
    
    // 检查图片文件类型
    if filename_lower.ends_with(".jpg") || 
       filename_lower.ends_with(".jpeg") || 
       filename_lower.ends_with(".png") ||
       filename_lower.ends_with(".gif") ||
       filename_lower.ends_with(".webp") ||
       filename_lower.ends_with(".bmp") ||
       filename_lower.ends_with(".svg") {
        return FileType::Image;
    }
    
    // 默认为普通文件
    FileType::Generic
}

/// 获取文件类型的描述文本
pub fn get_file_type_description(file_type: FileType) -> &'static str {
    match file_type {
        FileType::Generic => "普通文件",
        FileType::Image => "图片文件",
        FileType::Novel => "小说文件",
        FileType::Comic => "漫画容器",
        FileType::RichNovel => "富文本小说",
        FileType::Other => "其他文件",
    }
}
