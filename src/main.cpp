#include <glad/gl.h>
#include <GLFW/glfw3.h>
#include <imgui.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>

#include <cuda_runtime.h>

#include "rendering/ParticleSystem.cuh"

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>

static void glfw_error_callback(int error, const char* description) {
    std::fprintf(stderr, "GLFW Error %d: %s\n", error, description);
}

static std::string loadShaderSource(const char* filepath) {
    std::ifstream file(filepath);
    if (!file.is_open()) {
        std::fprintf(stderr, "Failed to open shader: %s\n", filepath);
        return "";
    }
    std::stringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

static unsigned int compileShader(unsigned int type, const char* source) {
    unsigned int shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);

    int success;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
    if (!success) {
        char infoLog[512];
        glGetShaderInfoLog(shader, 512, nullptr, infoLog);
        std::fprintf(stderr, "Shader compilation failed: %s\n", infoLog);
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

static unsigned int createShaderProgram(const char* vertPath, const char* fragPath) {
    std::string vertSource = loadShaderSource(vertPath);
    std::string fragSource = loadShaderSource(fragPath);

    if (vertSource.empty() || fragSource.empty()) {
        return 0;
    }

    unsigned int vertShader = compileShader(GL_VERTEX_SHADER, vertSource.c_str());
    unsigned int fragShader = compileShader(GL_FRAGMENT_SHADER, fragSource.c_str());

    if (!vertShader || !fragShader) {
        if (vertShader) glDeleteShader(vertShader);
        if (fragShader) glDeleteShader(fragShader);
        return 0;
    }

    unsigned int program = glCreateProgram();
    glAttachShader(program, vertShader);
    glAttachShader(program, fragShader);
    glLinkProgram(program);

    int success;
    glGetProgramiv(program, GL_LINK_STATUS, &success);
    if (!success) {
        char infoLog[512];
        glGetProgramInfoLog(program, 512, nullptr, infoLog);
        std::fprintf(stderr, "Shader linking failed: %s\n", infoLog);
        glDeleteProgram(program);
        program = 0;
    }

    glDeleteShader(vertShader);
    glDeleteShader(fragShader);

    return program;
}

int main() {
    glfwSetErrorCallback(glfw_error_callback);

    if (!glfwInit()) {
        std::fprintf(stderr, "Failed to initialize GLFW\n");
        return EXIT_FAILURE;
    }

    // OpenGL 4.6 Core
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 6);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    GLFWwindow* window = glfwCreateWindow(1280, 720, "Particle Simulation Framework", nullptr, nullptr);
    if (!window) {
        std::fprintf(stderr, "Failed to create GLFW window\n");
        glfwTerminate();
        return EXIT_FAILURE;
    }

    glfwMakeContextCurrent(window);
    glfwSwapInterval(1); // VSync

    // Load OpenGL functions
    int version = gladLoadGL(glfwGetProcAddress);
    if (version == 0) {
        std::fprintf(stderr, "Failed to initialize GLAD\n");
        glfwDestroyWindow(window);
        glfwTerminate();
        return EXIT_FAILURE;
    }
    std::printf("OpenGL %d.%d\n", GLAD_VERSION_MAJOR(version), GLAD_VERSION_MINOR(version));

    // Print CUDA device info
    int cudaDevice;
    cudaDeviceProp deviceProp;
    cudaGetDevice(&cudaDevice);
    cudaGetDeviceProperties(&deviceProp, cudaDevice);
    std::printf("CUDA Device: %s\n", deviceProp.name);

    // Setup Dear ImGui
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;

    ImGui::StyleColorsDark();

    ImGui_ImplGlfw_InitForOpenGL(window, true);
    ImGui_ImplOpenGL3_Init("#version 460");

    // Load particle shaders
    unsigned int particleShader = createShaderProgram(
        "shaders/particle.vert",
        "shaders/particle.frag"
    );
    if (!particleShader) {
        std::fprintf(stderr, "Failed to create particle shader program\n");
        // Continue anyway - will just not render particles
    }

    // Create VAO for particles
    unsigned int particleVAO = 0;
    glGenVertexArrays(1, &particleVAO);

    // Initialize particle system with CUDA-GL interop
    ParticleSystem particles;
    std::uint32_t particleCount = 100000;
    bool cudaInitialized = particleSystemInit(particles, particleCount);
    if (!cudaInitialized) {
        std::fprintf(stderr, "Failed to initialize particle system\n");
    }

    // Setup VAO with particle VBO
    if (cudaInitialized && particles.vbo) {
        glBindVertexArray(particleVAO);
        glBindBuffer(GL_ARRAY_BUFFER, particles.vbo);
        // float4: xy = position, zw = color/alpha
        glVertexAttribPointer(0, 4, GL_FLOAT, GL_FALSE, sizeof(float) * 4, nullptr);
        glEnableVertexAttribArray(0);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        glBindVertexArray(0);
    }

    // Enable point sprites and blending
    glEnable(GL_PROGRAM_POINT_SIZE);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    // Simulation state
    bool paused = false;
    float simulationSpeed = 1.0f;
    double lastTime = glfwGetTime();

    // Main loop
    while (!glfwWindowShouldClose(window)) {
        glfwPollEvents();

        double currentTime = glfwGetTime();
        float dt = static_cast<float>(currentTime - lastTime);
        lastTime = currentTime;

        // Update particles
        if (cudaInitialized && !paused) {
            particleSystemUpdate(particles, dt * simulationSpeed);
        }

        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplGlfw_NewFrame();
        ImGui::NewFrame();

        // Control panel
        ImGui::Begin("Particle Simulation");

        ImGui::Text("GPU: %s", deviceProp.name);
        ImGui::Text("Particles: %u", particleCount);
        ImGui::Text("FPS: %.1f", io.Framerate);

        ImGui::Separator();

        ImGui::Checkbox("Paused", &paused);
        ImGui::SliderFloat("Speed", &simulationSpeed, 0.1f, 5.0f);

        if (ImGui::Button("Reset")) {
            particleSystemDestroy(particles);
            cudaInitialized = particleSystemInit(particles, particleCount);

            if (cudaInitialized && particles.vbo) {
                glBindVertexArray(particleVAO);
                glBindBuffer(GL_ARRAY_BUFFER, particles.vbo);
                glVertexAttribPointer(0, 4, GL_FLOAT, GL_FALSE, sizeof(float) * 4, nullptr);
                glEnableVertexAttribArray(0);
                glBindBuffer(GL_ARRAY_BUFFER, 0);
                glBindVertexArray(0);
            }
        }

        ImGui::Separator();

        if (ImGui::Button("Exit")) {
            glfwSetWindowShouldClose(window, GLFW_TRUE);
        }

        ImGui::End();

        // Render
        int display_w, display_h;
        glfwGetFramebufferSize(window, &display_w, &display_h);
        glViewport(0, 0, display_w, display_h);
        glClearColor(0.05f, 0.05f, 0.08f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);

        // Draw particles
        if (cudaInitialized && particleShader && particles.vbo) {
            glUseProgram(particleShader);
            glBindVertexArray(particleVAO);
            glDrawArrays(GL_POINTS, 0, particles.count);
            glBindVertexArray(0);
            glUseProgram(0);
        }

        // Draw ImGui
        ImGui::Render();
        ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());

        glfwSwapBuffers(window);
    }

    // Cleanup
    particleSystemDestroy(particles);

    if (particleVAO) glDeleteVertexArrays(1, &particleVAO);
    if (particleShader) glDeleteProgram(particleShader);

    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();

    glfwDestroyWindow(window);
    glfwTerminate();

    return EXIT_SUCCESS;
}
